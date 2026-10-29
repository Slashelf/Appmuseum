import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_guia_v1/chat/chat_controller.dart';
import 'package:app_guia_v1/chat/chat_faq.dart';
import 'package:app_guia_v1/chat/chat_message.dart';
import 'package:app_guia_v1/chat/chat_voice.dart';
import 'package:app_guia_v1/chat/connection_check.dart';
import 'package:app_guia_v1/chat/guide_secrets.dart';
import 'package:app_guia_v1/chat/knowledge_source.dart';
import 'package:app_guia_v1/chat/conversation_store.dart';
import 'package:app_guia_v1/chat/local_exhibition_answers.dart';
import 'package:app_guia_v1/chat/local_guide_answer_service.dart';
import 'package:app_guia_v1/chat/local_knowledge_source.dart';
import 'package:app_guia_v1/chat/remote_guide_answer_service.dart';
import 'package:app_guia_v1/chat/visit_context.dart';
import 'package:app_guia_v1/chat/visit_memory.dart';
import 'package:app_guia_v1/core/locale/locale_controller.dart';
import 'package:app_guia_v1/core/theme/app_theme.dart';
import 'package:app_guia_v1/data/content_repository.dart';
import 'package:app_guia_v1/models/object_carousel_model.dart';
import 'package:app_guia_v1/models/object_model.dart';
import 'package:app_guia_v1/models/recommended_model.dart';
import 'package:app_guia_v1/screens/app_localizations.dart';
import 'package:app_guia_v1/screens/beacon_scan_services.dart';
import 'package:app_guia_v1/screens/chat_screen.dart';
import 'package:app_guia_v1/screens/guide_settings_screen.dart';
import 'package:app_guia_v1/screens/voice_conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    BeaconServiceFlutter().debugSkipPlugin = true;
  });
  const noData = 'sin datos';

  test('cripta answers with the stored San Francisco text', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Las criptas guardan el patrimonio funerario.',
    );
    final remote = _ScriptedRemote();
    final chat = _chat([
      sanFrancisco,
      _place(
        'maq',
        'Máquina de Laminado',
        'Equipo industrial de la Casa de Moneda.',
      ),
    ], visit: VisitContext()..updatePlace(sanFrancisco), remote: remote);
    await chat.submit('cripta', languageCode: 'es', noDataText: noData);
    expect(chat.messages.last.text, 'respuesta de la guia');
    expect(_facts(remote), contains('patrimonio funerario'));
    expect(chat.messages.last.text, isNot(contains('patrimonio funerario')));
    chat.dispose();
  });

  test('the visit summary is local and a new visit starts blank', () {
    final memory = VisitMemory();
    expect(memory.text, isEmpty);
    final seen = [
      const ChatMessage.visitor('¿Cuándo fue fundada?'),
      const ChatMessage.guide('Fundado en 1547.'),
    ];
    memory.rememberPlace('sf', 'Criptas de San Francisco', const []);
    memory.roll([
      ...seen,
      const ChatMessage.visitor('¿Qué muestran las imágenes?'),
    ], 4);
    expect(memory.text, isEmpty);
    memory.rememberPlace('merced', 'Criptas de La Merced', seen);
    expect(memory.boundary, seen.length);
    expect(memory.text, contains('Criptas de San Francisco'));
    expect(memory.text, contains('Fundado en 1547'));
    expect(memory.text, isNot(contains('Criptas de La Merced')));
    expect(VisitMemory().text, isEmpty);
  });

  test('an unrelated question is drafted by the model', () async {
    final remote = _ScriptedRemote();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas del templo.'),
    ], remote: remote);
    await chat.submit(
      'capital de francia',
      languageCode: 'es',
      noDataText: noData,
    );
    expect(remote.calls, 1);
    expect(chat.messages.last.text, 'respuesta de la guia');
    expect(chat.messages.last.text, isNot(contains('criptas del templo')));
    chat.dispose();
  });

  test('english uses the english text', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Historia de las criptas en español.',
      translations: {
        'en': {
          'name': 'Crypts of San Francisco',
          'description': 'The temple keeps colonial crypts of Potosi.',
        },
      },
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [sanFrancisco],
      visit: VisitContext()..updatePlace(sanFrancisco),
      remote: remote,
    );
    await chat.submit(
      'temple colonial crypts',
      languageCode: 'en',
      noDataText: noData,
    );
    expect(_facts(remote).toLowerCase(), contains('colonial crypts'));
    expect(_facts(remote).toLowerCase(), contains('potosi'));
    expect(_facts(remote), isNot(contains('español')));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('the current beacon place wins when both mention crypts', () async {
    final sanFrancisco = _place(
      'sf',
      'San Francisco',
      'Criptas del templo franciscano.',
    );
    final merced = _place(
      'merced',
      'La Merced',
      'Criptas del convento mercedario.',
    );
    final visit = VisitContext()..updatePlace(merced);
    final remote = _ScriptedRemote();
    final chat = _chat([sanFrancisco, merced], visit: visit, remote: remote);
    await chat.submit('criptas', languageCode: 'es', noDataText: noData);
    expect(remote.seen.single, hasLength(1));
    expect(remote.seen.single.first.id, 'merced');
    expect(remote.seen.single.first.fact, contains('mercedario'));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('every question sends the whole place card', () async {
    final sanFrancisco = _place(
      'sf',
      'San Francisco',
      'Criptas del templo.',
      openingHours: 'Horario de manana',
      direccion: 'Calle Matriz',
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [sanFrancisco],
      visit: VisitContext()..updatePlace(sanFrancisco),
      remote: remote,
    );
    await chat.submit('criptas', languageCode: 'es', noDataText: noData);
    expect(_facts(remote), contains('Criptas del templo'));
    expect(_facts(remote), contains('Horario de manana'));
    expect(_facts(remote), contains('Calle Matriz'));
    chat.dispose();
  });

  test('a greeting stays a greeting', () async {
    final remote = _ScriptedRemote();
    final chat = _chat([
      _place(
        'sf',
        'Criptas de San Francisco',
        'Las criptas guardan el patrimonio funerario.',
      ),
    ], remote: remote);
    await chat.submit('Hola', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 1);
    expect(chat.messages.last.text, 'respuesta de la guia');
    expect(chat.messages.last.text, isNot(contains('patrimonio')));
    expect(chat.messages.last.text, isNot(contains('no puedo hablar')));
    chat.dispose();
  });

  test('another exhibition is not sent unless its beacon is current', () async {
    final sanFrancisco = _place(
      'sf',
      'San Francisco',
      'Criptas del templo.',
      openingHours: 'Horario de manana',
    );
    final merced = _place(
      'merced',
      'La Merced',
      'Otro templo.',
      openingHours: 'Horario de tarde',
    );
    final withoutBeacon = _ScriptedRemote();
    final closed = _chat([sanFrancisco, merced], remote: withoutBeacon);
    await closed.submit('san francisco', languageCode: 'es', noDataText: noData);
    await closed.submit('horario', languageCode: 'es', noDataText: noData);
    expect(withoutBeacon.seen.last, isEmpty);
    expect(_facts(withoutBeacon), isNot(contains('Horario de manana')));
    expect(_facts(withoutBeacon), isNot(contains('Horario de tarde')));
    closed.dispose();

    final withBeacon = _ScriptedRemote();
    final open = _chat(
      [sanFrancisco, merced],
      visit: VisitContext()..updatePlace(sanFrancisco),
      remote: withBeacon,
    );
    await open.submit(
      'horario de la merced',
      languageCode: 'es',
      noDataText: noData,
    );
    expect(withBeacon.seen.single, hasLength(1));
    expect(withBeacon.seen.single.first.id, 'sf');
    expect(withBeacon.seen.single.first.fact, contains('Horario de manana'));
    expect(withBeacon.seen.single.first.fact, isNot(contains('tarde')));
    open.dispose();
  });

  test('a long place text is retold in a short phrase', () async {
    const stored = 'Las criptas del Convento de San Francisco en Potosí se encuentran '
        'en el subsuelo del altar mayor y fueron utilizadas durante la época colonial '
        'como lugares de entierro para frailes, clérigos y familias adineradas. '
        'Aunque hoy se conservan restos óseos antiguos.';
    final place = _place('sf', 'Criptas de San Francisco', stored);
    final remote = _ScriptedRemote();
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
    );
    await chat.submit('iglesia', languageCode: 'es', noDataText: noData);
    expect(chat.messages.last.text, 'respuesta de la guia');
    expect(_facts(remote), contains('subsuelo'));
    expect(_facts(remote), contains('frailes'));
    expect(_facts(remote), contains('óseos'));
    expect(chat.messages.last.text, isNot(contains('óseos')));
    chat.dispose();
  });

  test('a founder question sends the convent card and recent messages', () async {
    final place = _place(
      'sf',
      'Convento de San Francisco',
      'Entierros bajo el altar mayor.',
      cryptDescription: 'Templo de piedra con visitas guiadas.',
      openingHours: 'Lunes a viernes por la tarde',
      direccion: 'Calle Tarija',
      celular: '12345679',
      yearFounded: 1700,
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
    );
    await chat.submit('Hola', languageCode: 'es', noDataText: noData);
    await chat.submit('¿quién fundó este lugar?', languageCode: 'es', noDataText: noData);
    final card = remote.seen.last.single.fact;
    expect(remote.lastPlace, 'Convento de San Francisco');
    expect(card, contains('Entierros bajo el altar mayor'));
    expect(card, contains('Templo de piedra'));
    expect(card, contains('Lunes a viernes por la tarde'));
    expect(card, contains('Calle Tarija'));
    expect(card, isNot(contains('1700')));
    expect(card, isNot(contains('12345679')));
    expect(remote.lastHistory.last.text, '¿quién fundó este lugar?');
    expect(remote.lastHistory.any((message) => message.text == 'Hola'), isTrue);
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('a year in the prose is sent and the stored year field is not', () async {
    final place = _place(
      'ceca',
      'Casa de Moneda',
      'La ceca se fundó en 1572. El edificio es posterior.',
      celular: '12345679',
      yearFounded: 1700,
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
    );
    await chat.submit('de que ano es', languageCode: 'es', noDataText: noData);
    expect(_facts(remote), contains('1572'));
    expect(_facts(remote), contains('posterior'));
    expect(_facts(remote), isNot(contains('1700')));
    expect(_facts(remote), isNot(contains('12345679')));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('missing hours on the current place do not borrow another place', () async {
    final here = _place('sf', 'San Francisco', 'Criptas del templo.');
    final other = _place(
      'merced',
      'La Merced',
      'Otro templo.',
      openingHours: 'Horario de tarde',
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [here, other],
      visit: VisitContext()..updatePlace(here),
      remote: remote,
    );
    await chat.submit('horario', languageCode: 'es', noDataText: noData);
    expect(_facts(remote), isNot(contains('Horario de tarde')));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('deepseek mode without a key keeps the local fact and says so', () async {
    final visit = VisitContext();
    final chat = ChatController(
      store: MemoryConversationStore(),
      knowledge: LocalKnowledgeSource(_FakeRepository([
        _place(
          'sf',
          'San Francisco',
          'Criptas del templo.',
          openingHours: 'Horario de manana',
        ),
      ])),
      answers: LocalGuideAnswerService(),
      remote: RemoteGuideAnswerService(
        apiKey: '',
        fallback: LocalGuideAnswerService(),
      ),
      visit: visit,
    );
    await chat.setMode(ChatAnswerMode.deepseek, persist: false);
    await chat.submit(
      'horario',
      languageCode: 'es',
      noDataText: noData,
      aiUnavailableText: 'sin conexion',
    );
    expect(chat.messages.last.text, contains('Falta la clave'));
    expect(chat.messages.last.text, isNot(contains('Horario de manana')));
    expect(chat.messages.last.text, isNot(contains('Criptas del templo')));
    chat.dispose();
  });

  test('a new place does not clear the chat and the same place notifies once', () async {
    final first = _place('sf', 'San Francisco', 'Criptas del templo.');
    final second = _place('merced', 'La Merced', 'Criptas del convento.');
    final visit = VisitContext();
    var notices = 0;
    visit.addListener(() => notices++);
    visit.updatePlace(first);
    visit.updatePlace(first);
    expect(notices, 1);

    final chat = _chat([first, second], visit: visit);
    await chat.submit('criptas', languageCode: 'es', noDataText: noData);
    expect(chat.messages, hasLength(2));
    visit.updatePlace(second);
    expect(chat.messages, hasLength(2));
    expect(chat.messages.first.text, 'criptas');
    expect(notices, 2);
    chat.dispose();
  });

  testWidgets('the chat screen sends a question and shows the stored answer', (tester) async {
    final chat = _chat([
      _place(
        'sf',
        'Criptas de San Francisco',
        'Las criptas guardan el patrimonio funerario.',
      ),
    ]);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: LocaleController()),
          ChangeNotifierProvider.value(value: chat),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('es'), Locale('en'), Locale('de')],
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Pregúntame por esta exhibición'), findsOneWidget);
    expect(find.textContaining('Estás en'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'cripta');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.textContaining('respuesta de la guia'), findsOneWidget);
    expect(find.textContaining('se conserva'), findsNothing);
    expect(find.textContaining('No tengo ese dato'), findsNothing);
    chat.dispose();
  });

  test('the filter only blocks empty and spam questions', () async {
    final remote = _ScriptedRemote();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas guardan entierros.'),
    ], remote: remote);
    await chat.submit('   ', languageCode: 'es', noDataText: noData);
    expect(chat.messages, isEmpty);
    await chat.submit('https://ejemplo.test/aviso', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 0);
    expect(chat.messages.last.text, contains('lugares'));
    await chat.submit('dolor de cabeza', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 1);
    await chat.submit(
      'dolor de cabeza',
      languageCode: 'es',
      noDataText: noData,
      spoken: true,
      fromVoice: true,
    );
    expect(remote.calls, 2);
    expect(chat.messages.last.text, 'respuesta de la guia');
    await chat.submit('¿Cómo estás?', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 3);
    expect(chat.messages.last.text, 'respuesta de la guia');
    expect(ChatFaq.offTopicReply('en'), contains('places'));
    expect(ChatFaq.offTopicReply('de'), contains('Orten'));
    expect(ChatFaq.cannotDraft('en'), contains('draft'));
    expect(ChatFaq.cannotDraft('de'), contains('formulieren'));
    chat.dispose();
  });

  test('a misspelled question still sends only the beacon exhibition', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Entierros bajo el altar.',
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [
        sanFrancisco,
        _place('merced', 'Criptas de La Merced', 'Otra cripta.'),
      ],
      visit: VisitContext()..updatePlace(sanFrancisco),
      remote: remote,
    );
    await chat.submit('san fransisco', languageCode: 'es', noDataText: noData);
    expect(remote.seen.single, hasLength(1));
    expect(remote.seen.single.single.title, contains('San Francisco'));
    expect(_facts(remote), isNot(contains('Otra cripta')));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('what am I seeing uses the beacon place', () async {
    const stored = 'Las criptas del Convento de San Francisco en Potosí se encuentran '
        'en el subsuelo del altar mayor y fueron utilizadas durante la época colonial '
        'como lugares de entierro para frailes, clérigos y familias adineradas.';
    final place = _place('sf', 'Criptas de San Francisco', stored);
    final remote = _ScriptedRemote();
    final chat = _chat([place], visit: VisitContext()..updatePlace(place), remote: remote);
    await chat.submit('¿Qué estoy viendo?', languageCode: 'es', noDataText: noData);
    expect(remote.seen.single.first.id, 'sf');
    expect(_facts(remote), contains('subsuelo'));
    expect(_facts(remote), contains('frailes'));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('an unseen place still goes to the model', () async {
    final remote = _ScriptedRemote();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas del templo.'),
    ], remote: remote);
    await chat.submit('¿Qué lugar es este?', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 1);
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('how to get there uses the saved address', () async {
    final place = _place(
      'sf',
      'Criptas de San Francisco',
      'Las criptas del templo.',
      direccion: 'Calle Tarija',
    );
    final remote = _ScriptedRemote();
    final chat = _chat([place], visit: VisitContext()..updatePlace(place), remote: remote);
    await chat.submit('¿Cómo llego ahí?', languageCode: 'es', noDataText: noData);
    expect(_facts(remote), contains('Calle Tarija'));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('a route without an address still sends the place', () async {
    final place = _place('sf', 'San Francisco', 'Criptas del templo franciscano.');
    final remote = _ScriptedRemote();
    final chat = _chat([place], visit: VisitContext()..updatePlace(place), remote: remote);
    await chat.submit('¿Cómo llego a ese lugar?', languageCode: 'es', noDataText: noData);
    expect(_facts(remote), contains('franciscano'));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('crypts follow the current exhibition and change with the beacon', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Las criptas del Convento de San Francisco en Potosí se encuentran '
          'en el subsuelo del altar mayor y fueron utilizadas durante la época colonial '
          'como lugares de entierro para frailes, clérigos y familias adineradas.',
      cryptDescription: 'El convento y la iglesia son una construcción colonial.',
    );
    final merced = _place(
      'merced',
      'Criptas del Templo de La Merced',
      'Las criptas del Templo de La Merced en Potosí se encuentran '
          'en el subsuelo del edificio y fueron utilizadas durante la época colonial '
          'como lugares de entierro para religiosos, benefactores y personas de posición acomodada.',
      cryptDescription: 'La iglesia fue fundada por los mercedarios.',
    );
    final visit = VisitContext()..updatePlace(sanFrancisco);
    final remote = _ScriptedRemote();
    final chat = _chat(
      [sanFrancisco, merced],
      visit: visit,
      remote: remote,
    );
    await chat.submit('¿Cómo son las criptas?', languageCode: 'es', noDataText: noData);
    expect(_facts(remote), contains('frailes'));
    expect(_facts(remote), contains('construcción colonial'));
    expect(_facts(remote), isNot(contains('benefactores')));
    expect(remote.seen.single, hasLength(1));

    visit.updatePlace(merced);
    await chat.submit('¿Cómo son las criptas?', languageCode: 'es', noDataText: noData);
    expect(chat.messages, hasLength(4));
    expect(_facts(remote), contains('benefactores'));
    expect(_facts(remote), contains('mercedarios'));
    expect(_facts(remote), isNot(contains('frailes')));
    expect(remote.seen.last, hasLength(1));
    expect(remote.seen.last.single.id, 'merced');
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('switching beacons replaces the exhibition and never says the visitor is there', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Imágenes de las criptas franciscanas.',
      cryptDescription: 'Fundado en 1547.',
      openingHours: 'Lunes a Viernes 1ºTour 15:00 - 2ªTour 16:00',
      direccion: 'Calle Tarija, Esq. Nogales N°47',
    );
    final merced = _place(
      'merced',
      'Criptas de La Merced',
      'Imágenes de las criptas mercedarias.',
      cryptDescription: 'La iglesia fue construida entre 1555 y 1687.',
      openingHours: 'Lunes a Domingo: 09:00 a 12:00 / 14:30 a 18:00',
      direccion: 'Calle Hoyos Esq. Millares',
    );
    final visit = VisitContext()..updatePlace(sanFrancisco);
    final remote = _ScriptedRemote();
    final chat = _chat(
      [sanFrancisco, merced],
      visit: visit,
      remote: remote,
    );
    await chat.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    expect(chat.messages, hasLength(2));
    expect(remote.lastPlace, 'Criptas de San Francisco');
    final firstFacts = _facts(remote);
    expect(firstFacts, contains('Exhibición: Criptas de San Francisco'));
    expect(firstFacts, contains('Lugar que representa: Criptas de San Francisco'));
    expect(firstFacts, contains('Qué muestran las imágenes o piezas'));
    expect(firstFacts, contains('Calle Tarija'));
    expect(firstFacts, contains('Fundado en 1547'));
    expect(firstFacts, isNot(contains('Calle Hoyos')));
    expect(firstFacts, isNot(contains('14:30')));

    final system = (RemoteGuideAnswerService(
      apiKey: 'test',
      fallback: LocalGuideAnswerService(),
    ).buildBody(
      question: '¿Cuándo fue fundada?',
      languageCode: 'es',
      snippets: remote.seen.last,
      history: remote.lastHistory,
      placeName: remote.lastPlace,
    )['messages'] as List).first['content'] as String;
    expect(system, contains('Exhibición actual: Criptas de San Francisco'));
    expect(system.split('Exhibición actual:').first, isNot(contains('Criptas de San Francisco')));
    expect(system, contains('no está en el lugar real'));
    expect(system, contains('Exhibición actual'));
    expect(system, isNot(contains('El usuario está en')));
    expect(system, isNot(contains('14:30')));

    visit.updatePlace(merced);
    await chat.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    expect(chat.messages, hasLength(4));
    expect(chat.messages.first.text, '¿Cuándo fue fundada?');
    expect(remote.lastPlace, 'Criptas de La Merced');
    expect(remote.lastHistory, hasLength(1));
    expect(remote.lastSummary, contains('Criptas de San Francisco'));
    expect(remote.lastSummary, contains('respuesta de la guia'));
    expect(chat.messages, hasLength(4));
    final secondFacts = _facts(remote);
    expect(secondFacts, contains('Exhibición: Criptas de La Merced'));
    expect(secondFacts, contains('Calle Hoyos'));
    expect(secondFacts, contains('1555'));
    expect(secondFacts, isNot(contains('Calle Tarija')));
    expect(secondFacts, isNot(contains('1547')));
    expect(remote.seen.last, hasLength(1));
    expect(remote.seen.last.single.id, 'merced');

    final spanish = AppLocalizations(const Locale('es'));
    final english = AppLocalizations(const Locale('en'));
    final german = AppLocalizations(const Locale('de'));
    expect(spanish.get('chatHere'), 'Exhibición: {name}');
    expect(english.get('chatHere'), 'Exhibition: {name}');
    expect(german.get('chatHere'), 'Ausstellung: {name}');
    expect(spanish.get('chatWelcome'), contains('esta exhibición'));
    expect(english.get('chatWelcome'), contains('this exhibition'));
    expect(german.get('chatWelcome'), contains('dieser Ausstellung'));
    expect(spanish.get('chatHint'), 'Pregunta sobre esta exhibición');
    expect(english.get('chatHint'), 'Ask about this exhibition');
    expect(german.get('chatHint'), 'Fragen Sie zu dieser Ausstellung');
    chat.dispose();
  });

  test('focused questions keep the length rules and only the current exhibition', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Imágenes de las criptas franciscanas.',
      cryptDescription: 'Fundado en 1547.',
      openingHours: 'Lunes a Viernes 1ºTour 15:00 - 2ªTour 16:00',
      direccion: 'Calle Tarija, Esq. Nogales N°47',
      yearFounded: 1700,
    );
    final merced = _place(
      'merced',
      'Criptas de La Merced',
      'Imágenes de las criptas mercedarias.',
      cryptDescription: 'La iglesia fue construida entre 1555 y 1687.',
      openingHours: 'Lunes a Domingo: 09:00 a 12:00 / 14:30 a 18:00',
      direccion: 'Calle Hoyos Esq. Millares',
    );
    final machine = _place(
      'maq',
      'Máquina de Laminado',
      'La ceca comenzó a funcionar en 1572. El edificio se levantó entre 1759 y 1773.',
      openingHours: 'Lunes a Sábado: 09:00 - 16:30',
      direccion: 'Calle Bolívar, Potosí',
      celular: '12345679',
      yearFounded: 1700,
    );
    final visit = VisitContext()..updatePlace(sanFrancisco);
    final remote = _ScriptedRemote();
    final chat = _chat(
      [sanFrancisco, merced, machine],
      visit: visit,
      remote: remote,
    );

    Map<String, dynamic> packageFor(String question) {
      return RemoteGuideAnswerService(
        apiKey: 'test',
        fallback: LocalGuideAnswerService(),
      ).buildBody(
        question: question,
        languageCode: 'es',
        snippets: remote.seen.last,
        history: remote.lastHistory,
        placeName: remote.lastPlace,
        summary: remote.lastSummary,
      );
    }

    String systemOf(Map<String, dynamic> body) {
      return (body['messages'] as List).first['content'] as String;
    }

    await chat.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    final founded = packageFor('¿Cuándo fue fundada?');
    final foundedSystem = systemOf(founded);
    expect(founded['max_tokens'], 450);
    expect(founded['temperature'], 0.7);
    expect(foundedSystem, contains('2 o 3 frases como máximo'));
    expect(foundedSystem, contains('Fundado en 1547'));
    expect(foundedSystem, contains('Calle Tarija'));
    expect(foundedSystem, contains('Exhibición: Criptas de San Francisco'));
    expect(foundedSystem, isNot(contains('1700')));
    expect(foundedSystem, isNot(contains('yearFounded')));
    expect(foundedSystem, isNot(contains('12345679')));
    expect(foundedSystem, isNot(contains('1572')));
    expect(foundedSystem, isNot(contains('Calle Hoyos')));
    expect(foundedSystem, isNot(contains('El usuario está en')));
    expect(remote.seen.single, hasLength(1));
    expect(remote.seen.single.single.id, 'sf');

    await chat.submit('Cuéntame sobre esto', languageCode: 'es', noDataText: noData);
    final overview = packageFor('Cuéntame sobre esto');
    final overviewSystem = systemOf(overview);
    expect(overview['max_tokens'], 450);
    expect(overviewSystem, contains('6 a 8 frases'));
    expect(overviewSystem, contains('Nunca copies toda la información'));
    expect(overviewSystem, contains('Solo amplía si el usuario lo pide'));
    expect(overviewSystem, contains('Exhibición: Criptas de San Francisco'));
    expect(remote.seen.last.single.id, 'sf');

    await chat.submit('¿Qué es la Casa de Moneda?', languageCode: 'es', noDataText: noData);
    final mintSystem = systemOf(packageFor('¿Qué es la Casa de Moneda?'));
    expect(mintSystem, contains('relación histórica directa'));
    expect(mintSystem, contains('otra ciudad'));
    expect(mintSystem, isNot(contains('1572')));
    expect(mintSystem, isNot(contains('Calle Bolívar')));
    expect(mintSystem, isNot(contains('1759')));
    expect(mintSystem, isNot(contains('Máquina de Laminado')));
    expect(remote.seen.last, hasLength(1));
    expect(remote.seen.last.single.id, 'sf');

    visit.updatePlace(merced);
    await chat.submit('Cuéntame sobre esto', languageCode: 'es', noDataText: noData);
    final mercedBody = packageFor('Cuéntame sobre esto');
    final mercedSystem = systemOf(mercedBody);
    final dialogue = (mercedBody['messages'] as List)
        .where((message) => message['role'] != 'system')
        .toList();
    expect(chat.messages, hasLength(8));
    expect(chat.messages.first.text, '¿Cuándo fue fundada?');
    expect(remote.lastPlace, 'Criptas de La Merced');
    expect(mercedSystem, contains('Exhibición actual: Criptas de La Merced'));
    expect(
      mercedSystem.split('Resumen de la visita:').first,
      foundedSystem.split('Resumen de la visita:').first,
    );
    expect(mercedSystem, contains('6 a 8 frases'));
    expect(mercedSystem, contains('Calle Hoyos'));
    expect(mercedSystem, contains('1555'));
    expect(mercedSystem, isNot(contains('Calle Tarija')));
    expect(mercedSystem, isNot(contains('1547')));
    expect(mercedSystem, isNot(contains('1572')));
    expect(remote.seen.last.single.id, 'merced');
    expect(dialogue, hasLength(1));
    expect(dialogue.single['content'], 'Cuéntame sobre esto');
    expect(mercedSystem, contains('Criptas de San Francisco'));
    expect(mercedSystem, contains('¿Cuándo fue fundada?'));
    expect(remote.lastHistory.any((message) => message.text == '¿Cuándo fue fundada?'), isFalse);
    chat.dispose();
  });

  test('a church question uses the stored church text', () async {
    final place = _place(
      'sf',
      'Criptas de San Francisco',
      'Las criptas guardan entierros de frailes.',
      cryptDescription: 'La iglesia es barroca y se terminó en 1726.',
    );
    final remote = _ScriptedRemote();
    final chat = _chat([place], visit: VisitContext()..updatePlace(place), remote: remote);
    await chat.submit(
      '¿Qué historia tiene esta iglesia?',
      languageCode: 'es',
      noDataText: noData,
    );
    expect(_facts(remote), contains('barroca'));
    expect(_facts(remote), contains('1726'));
    expect(chat.messages.last.text, 'respuesta de la guia');
    chat.dispose();
  });

  test('without a model the chat does not paste the stored text', () async {
    final place = _place(
      'sf',
      'Criptas de San Francisco',
      'Las criptas del templo guardan restos de frailes.',
    );
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: RemoteGuideAnswerService(
        apiKey: '',
        fallback: LocalGuideAnswerService(),
      ),
    );
    await chat.submit('capital de francia', languageCode: 'es', noDataText: noData);
    expect(chat.messages.last.text, contains('Falta la clave'));
    expect(chat.messages.last.text, isNot(contains('frailes')));
    expect(ChatFaq.missingKey('en'), contains('key is missing'));
    expect(ChatFaq.missingKey('de'), contains('Schlüssel'));
    chat.dispose();
  });

  test('local mode answers the current exhibition and does not call the model', () async {
    final sanFrancisco = _place(
      'sf',
      'Criptas de San Francisco',
      'Imágenes de las criptas franciscanas.',
      cryptDescription: 'Fundado en 1547.',
      openingHours: 'Lunes a Viernes 1ºTour 15:00 - 2ªTour 16:00',
      direccion: 'Calle Tarija, Esq. Nogales N°47',
      yearFounded: 1700,
    );
    final merced = _place(
      'merced',
      'Criptas de La Merced',
      'Imágenes de las criptas mercedarias.',
      openingHours: 'Lunes a Domingo: 09:00 a 12:00 / 14:30 a 18:00',
      direccion: 'Calle Hoyos Esq. Millares',
    );
    final machine = _place(
      'maq',
      'Máquina de Laminado',
      'La ceca comenzó a funcionar en 1572. El edificio se levantó entre 1759 y 1773.',
      celular: '12345679',
      yearFounded: 1700,
    );
    final remote = _ScriptedRemote();
    final visit = VisitContext()..updatePlace(sanFrancisco);
    SharedPreferences.setMockInitialValues({});
    final chat = _chat(
      [sanFrancisco, merced, machine],
      visit: visit,
      remote: remote,
      mode: ChatAnswerMode.local,
    );

    await chat.askStored(
      LocalExhibitionQuestion.visit,
      languageCode: 'es',
      label: '¿Cómo visitarlo?',
    );
    expect(remote.calls, 0);
    expect(chat.messages.last.text, contains('exhibición sobre Criptas de San Francisco'));
    expect(chat.messages.last.text, contains('Calle Tarija'));
    expect(chat.messages.last.text, contains('15:00'));
    expect(chat.messages.last.text.toLowerCase(), isNot(contains('estás')));
    expect(chat.messages.last.text, isNot(contains('1700')));
    expect(chat.messages.last.text, isNot(contains('Calle Hoyos')));

    await chat.askStored(
      LocalExhibitionQuestion.founded,
      languageCode: 'es',
      label: '¿Cuándo se fundó?',
    );
    expect(remote.calls, 0);
    expect(chat.messages.last.text, contains('Fundado en 1547'));
    expect(chat.messages.last.text, isNot(contains('1700')));
    expect(chat.messages.last.text, isNot(contains('Imágenes de las criptas')));

    await chat.askStored(
      LocalExhibitionQuestion.images,
      languageCode: 'es',
      label: '¿Qué muestran estas imágenes?',
    );
    expect(chat.messages.last.text, contains('Imágenes de las criptas franciscanas'));
    expect(chat.messages.last.text, isNot(contains('Calle Tarija')));
    expect(chat.messages.last.text, isNot(contains('Fundado en 1547')));

    visit.updatePlace(merced);
    await chat.askStored(
      LocalExhibitionQuestion.visit,
      languageCode: 'es',
      label: '¿Cómo visitarlo?',
    );
    expect(remote.calls, 0);
    expect(chat.messages.last.text, contains('Calle Hoyos'));
    expect(chat.messages.last.text, contains('09:00'));
    expect(chat.messages.last.text, isNot(contains('Calle Tarija')));

    visit.updatePlace(machine);
    await chat.askStored(
      LocalExhibitionQuestion.founded,
      languageCode: 'es',
      label: '¿Cuándo se fundó?',
    );
    expect(chat.messages.last.text, contains('1572'));
    expect(chat.messages.last.text, isNot(contains('1700')));
    expect(chat.messages.last.text, isNot(contains('12345679')));
    expect(chat.messages.last.text, isNot(contains('1759')));

    final english = LocalExhibitionAnswers.reply(
      question: LocalExhibitionQuestion.visit,
      place: sanFrancisco,
      languageCode: 'en',
    );
    final german = LocalExhibitionAnswers.reply(
      question: LocalExhibitionQuestion.visit,
      place: sanFrancisco,
      languageCode: 'de',
    );
    expect(english, contains('Calle Tarija'));
    expect(english, isNot(contains('You are')));
    expect(german, contains('Calle Tarija'));
    expect(german, isNot(contains('Sie sind')));

    final bare = _place('bare', 'Sin datos', '');
    final missing = LocalExhibitionAnswers.reply(
      question: LocalExhibitionQuestion.visit,
      place: bare,
      languageCode: 'es',
    );
    expect(missing, contains('no tiene la dirección ni el horario'));

    await chat.setMode(ChatAnswerMode.deepseek);
    expect(
      (await SharedPreferences.getInstance()).getString(ChatController.modeStorageKey),
      'deepseek',
    );
    await chat.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 1);
    expect(remote.lastPlace, 'Máquina de Laminado');

    await chat.setMode(ChatAnswerMode.local);
    expect(
      (await SharedPreferences.getInstance()).getString(ChatController.modeStorageKey),
      'local',
    );
    await chat.submit('hola', languageCode: 'es', noDataText: noData);
    expect(remote.calls, 1);
    expect(chat.messages.last.text, contains('modo local'));
    chat.dispose();
  });

  testWidgets('the mode switch keeps local answers offline and remembers the choice', (tester) async {
    final place = _place(
      'sf',
      'Criptas de San Francisco',
      'Imágenes de las criptas franciscanas.',
      direccion: 'Calle Tarija, Esq. Nogales N°47',
      openingHours: 'Lunes a Viernes 1ºTour 15:00',
    );
    final remote = _ScriptedRemote();
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
      mode: ChatAnswerMode.local,
    );
    SharedPreferences.setMockInitialValues({});
    Future<void> show(ChatController controller) {
      return tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: LocaleController()),
            ChangeNotifierProvider.value(value: controller),
          ],
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
            home: ChatScreen(key: ObjectKey(controller)),
          ),
        ),
      );
    }

    await show(chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Modo local'), findsOneWidget);
    expect(find.text('Modo chatbot'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-mode-local')));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('chat-mic')), findsNothing);
    expect(find.text('¿Cuándo se fundó?'), findsOneWidget);
    expect(find.text('¿Qué muestran estas imágenes?'), findsOneWidget);
    expect(find.text('¿Cómo visitarlo?'), findsOneWidget);
    expect(AppLocalizations(const Locale('en')).get('modeChatbotLabel'), 'Chatbot mode');
    expect(AppLocalizations(const Locale('de')).get('modeLocalLabel'), 'Lokaler Modus');

    final rowScroll = find.descendant(
      of: find.byKey(const Key('chat-local-row')),
      matching: find.byType(Scrollable),
    );
    final rowPosition = tester.state<ScrollableState>(rowScroll).position;
    rowPosition.jumpTo(rowPosition.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-local-visit')));
    await tester.pumpAndSettle();
    expect(remote.calls, 0);
    expect(find.textContaining('Calle Tarija'), findsOneWidget);
    expect(find.textContaining('estás'), findsNothing);

    expect(find.text('Exhibición: Criptas de San Francisco'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-local-hide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-local-visit')), findsNothing);
    await tester.tap(find.byKey(const Key('chat-local-show')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-local-visit')), findsOneWidget);
    final radio = BeaconServiceFlutter();
    radio.debugPrepare(scanEnabled: true, scanningNow: false, alive: false);
    radio.session.markOpen('exhibicion-viva');
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-mode-chatbot')));
    await tester.pumpAndSettle();
    expect(chat.visit.place?.id, 'sf');
    expect(find.text('Exhibición: Criptas de San Francisco'), findsOneWidget);
    expect(radio.watch.recoveries, 1);
    expect(radio.session.open.contains('exhibicion-viva'), isTrue);
    expect(find.byKey(const Key('chat-mic')), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Pega aquí la clave de DeepSeek'), findsNothing);
    expect(find.byKey(const Key('chat-eleven-key')), findsNothing);
    expect(find.byKey(const Key('chat-local-visit')), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(ChatController.modeStorageKey),
      'deepseek',
    );

    final restored = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
      mode: ChatAnswerMode.local,
    );
    await show(restored);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-mic')), findsOneWidget);
    expect(find.byKey(const Key('chat-local-founded')), findsNothing);
    chat.dispose();
    restored.dispose();
  });

  test('listening stops on silence and never runs past one minute', () {
    final spanish = chatListenOptions('es_ES');
    expect(spanish.pauseFor, const Duration(seconds: 3));
    expect(chatHoldListenOptions('es_ES').pauseFor, chatListenLimit);
    expect(spanish.listenFor, const Duration(seconds: 60));
    expect(spanish.listenMode, ListenMode.dictation);
    expect(spanish.partialResults, isTrue);
    expect(spanish.localeId, 'es_ES');
    expect(chatListenOptions('en_US').localeId, 'en_US');
    expect(chatListenOptions('de_DE').localeId, 'de_DE');
    expect(AppLocalizations(const Locale('es')).get('micNotHeard'), 'No te escuché, intenta de nuevo');
    expect(AppLocalizations(const Locale('es')).get('micSlideCancel'), 'Desliza para cancelar');
    expect(AppLocalizations(const Locale('en')).get('micSlideCancel'), 'Slide to cancel');
    expect(AppLocalizations(const Locale('de')).get('micSlideCancel'), contains('wischen'));
    expect(AppLocalizations(const Locale('en')).get('micLocked'), 'Recording locked');
    expect(AppLocalizations(const Locale('de')).get('micLocked'), 'Aufnahme fixiert');
    expect(AppLocalizations(const Locale('en')).get('micNotHeard'), contains('hear'));
    expect(AppLocalizations(const Locale('de')).get('micNotHeard'), contains('gehört'));
    expect(AppLocalizations(const Locale('en')).get('micExplainBody'), contains('microphone'));
    expect(AppLocalizations(const Locale('de')).get('micExplainBody'), contains('Mikrofon'));
  });

  testWidgets('the microphone listens, cancels, and can speak a reply', (tester) async {
    final ear = _FakeEar();
    final speaker = _FakeSpeaker();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas del templo.'),
    ]);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: LocaleController()),
          ChangeNotifierProvider.value(value: chat),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
          home: ChatScreen(ear: ear, speaker: speaker),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    final menu = tester.widget<PopupMenuButton<String>>(find.byKey(const Key('chat-menu')));
    expect(menu.color, GuidePalette.surface);
    expect((menu.shape as RoundedRectangleBorder).side.color, GuidePalette.accent);
    final voiceItem = tester.widget<GuideMenuItem>(find.byKey(const Key('chat-voice')));
    final autoItem = tester.widget<GuideMenuItem>(find.byKey(const Key('chat-auto-send')));
    expect(voiceItem.checked, isFalse);
    expect(autoItem.checked, isFalse);
    expect(
      find.descendant(of: find.byKey(const Key('chat-talk')), matching: find.byIcon(Icons.mic_none)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('chat-talk')), matching: find.text('Hablar')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('chat-mode-chatbot')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-mic')));
    await tester.pumpAndSettle();
    expect(find.text('Para dictar tu pregunta, la app usa el micrófono. Solo escucha cuando tú lo activas.'), findsOneWidget);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(ear.prepares, 0);

    await tester.tap(find.byKey(const Key('chat-mic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(ear.prepares, 0);
    expect(ear.listens, 0);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('chat-mic'))));
    await tester.pump();
    await tester.pump();
    expect(ear.prepares, 1);
    expect(ear.listens, 1);
    expect(ear.localeId, 'es_ES');
    expect(ear.options?.pauseFor, chatListenLimit);
    expect(find.byKey(const Key('chat-mic-level')), findsOneWidget);
    expect(find.text('Desliza para cancelar'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);

    ear.onLevel?.call(8);
    await tester.pump();
    expect(find.byKey(const Key('chat-mic-level')), findsOneWidget);
    ear.onWords?.call('criptas de san francisco', false);
    await tester.pump();

    await tester.tap(find.byKey(const Key('chat-mic-cancel')));
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(ear.cancels, 1);
    expect(find.text('criptas de san francisco'), findsNothing);
    expect(find.text('No te escuché, intenta de nuevo'), findsNothing);
    expect(chat.messages, isEmpty);

    final beforeHold = ear.listens;
    final empty = await tester.startGesture(tester.getCenter(find.byKey(const Key('chat-mic'))));
    await tester.pump();
    await tester.pump();
    expect(ear.listens, beforeHold + 1);
    await empty.up();
    await tester.pumpAndSettle();
    expect(ear.stops, greaterThan(0));
    expect(find.text('No te escuché, intenta de nuevo'), findsOneWidget);
    expect(chat.messages, isEmpty);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'cripta');
    await tester.pump();
    expect(find.byKey(const Key('chat-send')), findsOneWidget);
    expect(find.byKey(const Key('chat-mic')), findsNothing);
    await tester.tap(find.byKey(const Key('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('respuesta de la guia'), findsOneWidget);
    expect(speaker.lastText, isNull);

    await tester.tap(find.byKey(const Key('chat-speak-1')));
    await tester.pump();
    expect(speaker.lastText, 'respuesta de la guia');
    expect(find.byIcon(Icons.stop), findsOneWidget);
    final listensBeforeVoice = ear.listens;
    speaker.finish();
    await tester.pumpAndSettle();
    expect(ear.listens, listensBeforeVoice);

    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-speak-1')));
    await tester.pump();
    speaker.finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(ear.listens, listensBeforeVoice + 1);
    expect(ear.options?.pauseFor, const Duration(seconds: 3));
    expect(find.byKey(const Key('chat-mic-level')), findsOneWidget);
    chat.dispose();
  });

  testWidgets('hold sends, a left slide cancels, and the lock keeps recording', (tester) async {
    final ear = _FakeEar();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas del templo.'),
    ]);
    SharedPreferences.setMockInitialValues({
      'chat_mic_explained': true,
      ChatController.modeStorageKey: 'deepseek',
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: LocaleController()),
          ChangeNotifierProvider.value(value: chat),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
          home: ChatScreen(ear: ear, speaker: _FakeSpeaker()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-mic')), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'cripta');
    await tester.pump();
    expect(find.byKey(const Key('chat-send')), findsOneWidget);
    expect(find.byKey(const Key('chat-mic')), findsNothing);
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump();
    expect(find.byKey(const Key('chat-mic')), findsOneWidget);

    Future<TestGesture> down() {
      return tester.startGesture(tester.getCenter(find.byKey(const Key('chat-mic'))));
    }

    final send = await down();
    await tester.pump();
    await tester.pump();
    expect(find.text('Desliza para cancelar'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.byKey(const Key('chat-mic-level')), findsOneWidget);
    ear.onWords?.call('hola guia', true);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);
    await send.up();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(ear.stops, greaterThan(0));
    expect(find.text('hola guia'), findsOneWidget);
    expect(chat.messages.map((message) => message.text), contains('hola guia'));

    final beforeCancel = ear.cancels;
    final beforeMessages = chat.messages.length;
    final slide = await down();
    await tester.pump();
    await tester.pump();
    ear.onWords?.call('no enviar', true);
    await tester.pump();
    await slide.moveBy(const Offset(-140, 0));
    await tester.pump();
    await slide.up();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(ear.cancels, beforeCancel + 1);
    expect(chat.messages.length, beforeMessages);
    expect(find.text('no enviar'), findsNothing);

    final stops = ear.stops;
    final lock = await down();
    await tester.pump();
    await tester.pump();
    ear.onWords?.call('sigue grabando', true);
    await lock.moveBy(const Offset(0, -140));
    await tester.pump();
    expect(find.byKey(const Key('chat-mic-lock')), findsOneWidget);
    expect(find.text('Grabación fija'), findsOneWidget);
    await lock.up();
    await tester.pump();
    expect(ear.stops, stops);
    expect(chat.messages.length, beforeMessages);
    expect(find.byKey(const Key('chat-mic-clock')), findsOneWidget);
    expect(find.byKey(const Key('chat-mic-level')), findsOneWidget);
    expect(find.byKey(const Key('chat-mic-send')), findsOneWidget);
    chat.dispose();
  });

  test('typing and jump labels exist in Spanish, English and German', () {
    expect(AppLocalizations(const Locale('es')).get('chatTyping'), 'Escribiendo…');
    expect(AppLocalizations(const Locale('en')).get('chatTyping'), 'Typing…');
    expect(AppLocalizations(const Locale('de')).get('chatTyping'), 'Schreibt…');
    expect(AppLocalizations(const Locale('es')).get('chatJump'), 'Bajar al final');
    expect(AppLocalizations(const Locale('en')).get('chatJump'), 'Jump to the latest');
    expect(AppLocalizations(const Locale('de')).get('chatJump'), 'Nach unten');
  });

  testWidgets('a parked thread stays put and a followed long reply opens at the top', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final remote = _HeldRemote();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas guardan entierros.'),
    ], remote: remote);
    for (var i = 0; i < 8; i++) {
      await _ask(tester, chat, remote, 'pregunta $i', 'respuesta corta $i');
    }
    SharedPreferences.setMockInitialValues({});
    await _showChat(tester, chat);
    await tester.pumpAndSettle();

    final thread = find.byKey(const Key('chat-thread'));
    expect(_threadOffset(tester), closeTo(_threadExtent(tester), 2));
    expect(find.byKey(const Key('chat-jump')), findsNothing);

    await tester.drag(thread, const Offset(0, 320));
    await tester.pumpAndSettle();
    final parked = _threadOffset(tester);
    expect(parked, lessThan(_threadExtent(tester) - 48));
    expect(find.byKey(const Key('chat-jump')), findsOneWidget);
    expect(find.text('↓'), findsOneWidget);
    expect(find.byTooltip('Bajar al final'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_threadOffset(tester), closeTo(parked, 1));

    await tester.enterText(find.byType(TextField).last, 'mensaje nuevo');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(_threadOffset(tester), closeTo(parked, 2));
    expect(find.byKey(const Key('chat-jump')), findsOneWidget);
    expect(chat.messages.last.text, 'mensaje nuevo');
    expect(find.text('mensaje nuevo'), findsNothing);

    remote.gate!.complete('respuesta mientras leía arriba');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_threadOffset(tester), closeTo(parked, 2));
    expect(find.byKey(const Key('chat-jump')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_threadOffset(tester), closeTo(parked, 2));

    await tester.tap(find.byKey(const Key('chat-jump')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-jump')), findsNothing);
    expect(_threadOffset(tester), closeTo(_threadExtent(tester), 2));

    await tester.enterText(find.byType(TextField).last, 'pregunta desde el final');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Escribiendo…'), findsOneWidget);
    final followedList = tester.getRect(thread);
    final questionRect = tester.getRect(find.text('pregunta desde el final'));
    expect(questionRect.top, greaterThanOrEqualTo(followedList.top - 1));
    expect(questionRect.bottom, lessThanOrEqualTo(followedList.bottom + 1));

    const line = 'Línea de la respuesta larga sobre las criptas.';
    remote.gate!.complete(List.filled(60, line).join('\n'));
    await tester.pump();
    await tester.pumpAndSettle();

    final replyRect = tester.getRect(find.textContaining(line));
    final threadRect = tester.getRect(thread);
    expect((replyRect.top - threadRect.top).abs(), lessThan(36));
    expect(find.byKey(const Key('chat-jump')), findsOneWidget);
    expect(_threadOffset(tester), lessThan(_threadExtent(tester) - 48));

    final opened = _threadOffset(tester);
    await tester.drag(thread, const Offset(0, 220));
    await tester.pumpAndSettle();
    final higher = _threadOffset(tester);
    expect(higher, lessThan(opened - 40));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_threadOffset(tester), closeTo(higher, 1));
    expect(_threadOffset(tester), lessThan(_threadExtent(tester) - 48));
    chat.dispose();
  });

  testWidgets('the keyboard keeps the visible line above the composer', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final remote = _HeldRemote();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas guardan entierros.'),
    ], remote: remote);
    for (var i = 0; i < 8; i++) {
      await _ask(tester, chat, remote, 'pregunta $i', 'respuesta corta $i');
    }
    SharedPreferences.setMockInitialValues({});
    final locale = LocaleController();
    await _showChat(tester, chat, locale: locale, keyboard: 0);
    await tester.pumpAndSettle();

    final last = find.text('respuesta corta 7');
    final thread = find.byKey(const Key('chat-thread'));
    var threadRect = tester.getRect(thread);
    var lastRect = tester.getRect(last);
    expect(lastRect.top, greaterThanOrEqualTo(threadRect.top - 1));
    expect(lastRect.bottom, lessThanOrEqualTo(threadRect.bottom + 1));

    await _showChat(tester, chat, locale: locale, keyboard: 240);
    await tester.pump();
    threadRect = tester.getRect(thread);
    lastRect = tester.getRect(last);
    expect(lastRect.bottom, lessThanOrEqualTo(threadRect.bottom + 1));
    expect(lastRect.top, greaterThanOrEqualTo(threadRect.top - 1));
    expect(_threadOffset(tester), closeTo(_threadExtent(tester), 2));

    await tester.drag(thread, const Offset(0, 360));
    await tester.pumpAndSettle();
    final parked = _threadOffset(tester);
    expect(parked, lessThan(_threadExtent(tester) - 48));

    await _showChat(tester, chat, locale: locale, keyboard: 420);
    await tester.pump();
    expect(_threadOffset(tester), lessThan(_threadExtent(tester) - 48));
    expect(_threadOffset(tester), greaterThan(parked + 40));
    expect(_threadOffset(tester), lessThan(parked + 260));
    chat.dispose();
  });

  test('a voice turn without internet does not invent a guide answer', () async {
    final remote = _OfflineRemote();
    final chat = _chat([
      _place('sf', 'Criptas de San Francisco', 'Las criptas.'),
    ], remote: remote);
    await chat.submit(
      'cuando se fundo',
      languageCode: 'es',
      noDataText: noData,
      spoken: true,
      fromVoice: true,
    );
    expect(chat.tookOffline, isTrue);
    expect(chat.messages, hasLength(1));
    expect(chat.messages.single.text, 'cuando se fundo');
    chat.dispose();
  });

  test('a deepseek failure is said plainly and does not look like a drafted answer', () async {
    final place = _place('sf', 'Criptas de San Francisco', 'Las criptas del templo guardan restos.');
    final offline = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: _ErrorRemote(const SocketException('offline')),
    );
    await offline.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    expect(offline.tookOffline, isTrue);
    expect(offline.messages.last.text, 'No pude conectar, intenta de nuevo.');
    expect(offline.messages.last.text, isNot(contains('restos')));
    expect(ChatFaq.couldNotConnect('en'), 'I could not connect. Try again.');
    expect(ChatFaq.couldNotConnect('de'), contains('Verbindung'));
    offline.dispose();

    final credit = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: _ErrorRemote(
        const DeepSeekException(credit: true, status: 402, detail: 'Insufficient Balance'),
      ),
    );
    await credit.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    expect(credit.tookOffline, isFalse);
    expect(credit.messages.last.text, contains('crédito'));
    expect(credit.messages.last.text, isNot(contains('restos')));
    expect(ChatFaq.noCredit('en'), contains('no credit'));
    expect(ChatFaq.noCredit('de'), contains('Guthaben'));
    credit.dispose();

    final voice = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: _ErrorRemote(const SocketException('offline')),
    );
    await voice.submit(
      'cuando se fundo',
      languageCode: 'es',
      noDataText: noData,
      spoken: true,
      fromVoice: true,
    );
    expect(voice.tookOffline, isTrue);
    expect(voice.messages, hasLength(1));
    expect(voice.messages.single.text, 'cuando se fundo');
    voice.dispose();
  });

  testWidgets('the voice screen cycles, pauses, and leaves the chat', (tester) async {
    final ear = _FakeEar();
    final remote = _ScriptedRemote();
    final place = _place('sf', 'Criptas de San Francisco', 'Las criptas del templo.');
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
    );
    final spoken = <String>[];
    final hang = Completer<void>();
    SharedPreferences.setMockInitialValues({});

    Future<void> show(
      Future<void> Function(String sentence, String languageCode)? onSpeak, {
      required bool online,
      required String name,
    }) {
      return tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: LocaleController()),
            ChangeNotifierProvider.value(value: chat),
          ],
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
            home: VoiceConversationScreen(
              key: ValueKey(name),
              ear: ear,
              online: () async => online,
              onSpeak: onSpeak,
            ),
          ),
        ),
      );
    }

    Future<void> untilListening(int count) async {
      for (var i = 0; i < 20 && ear.listens < count; i++) {
        await tester.pump();
      }
      await tester.pump();
    }

    Future<void> untilReady(bool Function() ready) async {
      for (var i = 0; i < 20 && !ready(); i++) {
        await tester.pump();
      }
    }

    await show(null, online: false, name: 'offline');
    await untilReady(() => find.byKey(const Key('voice-offline')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('voice-offline')), findsOneWidget);
    expect(find.text('Sin internet. La conversación por voz necesita conexión.'), findsOneWidget);
    expect(ear.listens, 0);
    expect(remote.calls, 0);
    expect(AppLocalizations(const Locale('en')).get('voiceTapToContinue'), 'Tap to continue');
    expect(AppLocalizations(const Locale('de')).get('voiceOffline'), contains('Internet'));

    await show((sentence, language) async => spoken.add(sentence), online: true, name: 'online');
    await untilListening(1);
    expect(find.text('Exhibición: Criptas de San Francisco'), findsOneWidget);
    expect(find.byKey(const Key('voice-offline')), findsNothing);
    expect(ear.listens, 1);
    expect(ear.options?.pauseFor, chatListenLimit);
    expect(ear.options?.cancelOnError, isFalse);

    ear.onWords?.call('cuando se fundo', false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
    await untilReady(() => remote.calls >= 1 && spoken.isNotEmpty);
    expect(remote.calls, 1);
    expect(remote.lastLimit, 4);
    expect(chat.messages.first.text, 'cuando se fundo');
    expect(spoken, ['respuesta de la guia']);
    expect(find.byKey(const Key('voice-user-line')), findsOneWidget);
    expect(find.byKey(const Key('voice-guide-line')), findsOneWidget);

    final afterReply = ear.listens;
    await untilListening(afterReply + 1);
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Toca para seguir'), findsWidgets);

    final before = remote.calls;
    final beforeListen = ear.listens;
    await show((sentence, language) => hang.future, online: true, name: 'interrupt');
    await untilListening(beforeListen + 1);
    ear.onWords?.call('otra pregunta', false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
    await untilReady(() => remote.calls > before && find.text('Hablando').evaluate().isNotEmpty);
    expect(remote.calls, before + 1);
    expect(find.text('Hablando'), findsOneWidget);
    final speakingOrb = tester.widget<CustomPaint>(find.descendant(
      of: find.byKey(const Key('voice-sphere')),
      matching: find.byType(CustomPaint),
    ));
    expect((speakingOrb.painter as MuseumOrbPainter).phase, VoicePhase.speaking);
    await tester.tap(find.byKey(const Key('voice-sphere')));
    await untilReady(() => find.text('Escuchando').evaluate().isNotEmpty);
    expect(find.text('Escuchando'), findsOneWidget);
    final listeningOrb = tester.widget<CustomPaint>(find.descendant(
      of: find.byKey(const Key('voice-sphere')),
      matching: find.byType(CustomPaint),
    ));
    expect((listeningOrb.painter as MuseumOrbPainter).phase, VoicePhase.listening);
    hang.complete();
    await tester.pump();

    await tester.tap(find.byKey(const Key('voice-exit')));
    await tester.pump();
    await tester.pump();
    expect(chat.messages.length, greaterThan(1));
    chat.dispose();
  });

  testWidgets('talk mode keeps listening after hola and a dropped ear', (tester) async {
    final ear = _FakeEar();
    final remote = _ScriptedRemote();
    final chat = _chat([], remote: remote);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: LocaleController()),
          ChangeNotifierProvider.value(value: chat),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
          home: VoiceConversationScreen(
            ear: ear,
            online: () async => true,
            onSpeak: (sentence, language) async {},
          ),
        ),
      ),
    );

    Future<void> untilListening(int count) async {
      for (var i = 0; i < 20 && ear.listens < count; i++) {
        await tester.pump();
      }
    }

    await untilListening(1);
    expect(ear.listens, 1);

    ear.onWords?.call('hola', false);
    await tester.pump();
    ear.onStatus?.call('done');
    await untilListening(2);
    expect(remote.calls, 0);
    expect(find.text('hola'), findsOneWidget);

    ear.onWords?.call('cuando se fundo', false);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(remote.calls, 0);
    await tester.pump(const Duration(milliseconds: 1400));
    for (var i = 0; i < 20 && remote.calls < 1; i++) {
      await tester.pump();
    }
    expect(remote.calls, 1);
    expect(chat.messages.first.text, 'hola cuando se fundo');

    await untilListening(ear.listens + 1);
    final beforeErrors = ear.listens;
    ear.onError?.call();
    await untilListening(beforeErrors + 1);
    expect(find.text('Toca para seguir'), findsNothing);
    ear.onError?.call();
    await untilListening(beforeErrors + 2);
    ear.onError?.call();
    await tester.pump();
    expect(find.text('Toca para seguir'), findsWidgets);
    chat.dispose();
  });

  test('the museum orb paints listen, think, and speak', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = Size(220, 220);
    final listening = MuseumOrbPainter(phase: VoicePhase.listening, pulse: 0.2, level: 0.85);
    final thinking = MuseumOrbPainter(phase: VoicePhase.thinking, pulse: 0.6, level: 0);
    final speaking = MuseumOrbPainter(phase: VoicePhase.speaking, pulse: 0.3, level: 0);
    listening.paint(canvas, size);
    thinking.paint(canvas, size);
    speaking.paint(canvas, size);
    expect(listening.shouldRepaint(thinking), isTrue);
    expect(thinking.shouldRepaint(speaking), isTrue);
    expect(speaking.shouldRepaint(MuseumOrbPainter(phase: VoicePhase.speaking, pulse: 0.3, level: 0)), isFalse);
    recorder.endRecording().dispose();
  });

  test('plain preference keys move into the secret store', () async {
    SharedPreferences.setMockInitialValues({
      ChatController.keyStorageKey: 'deep-old',
      ChatController.elevenKeyStorageKey: 'eleven-old',
      ChatController.elevenVoiceStorageKey: 'voice-old',
    });
    final secrets = MemoryGuideSecretStore();
    final remote = _ScriptedRemote();
    final chat = _chat(
      [],
      remote: remote,
      secrets: secrets,
    );
    await chat.restoreSaved();
    expect(chat.runtimeKey, 'deep-old');
    expect(remote.apiKey, 'deep-old');
    expect(chat.elevenKey, 'eleven-old');
    expect(chat.elevenVoiceId, 'voice-old');
    expect(await secrets.read(ChatController.keyStorageKey), 'deep-old');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ChatController.keyStorageKey), isNull);
    expect(prefs.getString(ChatController.elevenKeyStorageKey), isNull);
    expect(prefs.getString(ChatController.elevenVoiceStorageKey), isNull);
    chat.updateElevenKey('clave-larga-sin-heuristica');
    chat.updateVoiceId('otra-voz-123456');
    expect(chat.elevenKey, 'clave-larga-sin-heuristica');
    expect(chat.elevenVoiceId, 'otra-voz-123456');
    expect(await secrets.read(ChatController.elevenKeyStorageKey), 'clave-larga-sin-heuristica');
    expect(await secrets.read(ChatController.elevenVoiceStorageKey), 'otra-voz-123456');
    chat.updateElevenKey('');
    expect(chat.elevenKey, isEmpty);
    expect(chat.elevenVoiceId, 'otra-voz-123456');
    chat.dispose();
  });

  test('a compiled key stays ahead of a saved key', () async {
    SharedPreferences.setMockInitialValues({
      ChatController.keyStorageKey: 'saved-deep',
      ChatController.elevenKeyStorageKey: 'saved-eleven',
    });
    final secrets = MemoryGuideSecretStore();
    final remote = _ScriptedRemote();
    final chat = _chat(
      [],
      remote: remote,
      secrets: secrets,
      compiledKey: 'compiled-deep',
    );
    await chat.restoreSaved();
    expect(remote.apiKey, 'compiled-deep');
    expect(chat.deepSeekKey, 'compiled-deep');
    expect(await secrets.read(ChatController.keyStorageKey), 'saved-deep');
    expect(await secrets.read(ChatController.elevenKeyStorageKey), 'saved-eleven');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(ChatController.keyStorageKey), isFalse);
    expect(prefs.containsKey(ChatController.elevenKeyStorageKey), isFalse);
    chat.updateDeepSeekKey('typed-over');
    expect(remote.apiKey, 'compiled-deep');
    expect(chat.deepSeekKey, 'compiled-deep');
    chat.dispose();
  });

  test('clearing the conversation drops the thread and the summary', () async {
    final place = _place('sf', 'Criptas de San Francisco', 'Las criptas del templo.');
    final remote = _ScriptedRemote();
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
    );
    await chat.submit('¿Cuándo fue fundada?', languageCode: 'es', noDataText: noData);
    expect(chat.messages, hasLength(2));
    chat.clearConversation();
    expect(chat.messages, isEmpty);
    await chat.submit('otra pregunta', languageCode: 'es', noDataText: noData);
    expect(remote.lastSummary, isEmpty);
    expect(remote.lastHistory, hasLength(1));
    expect(remote.lastHistory.single.text, 'otra pregunta');
    chat.dispose();
  });

  testWidgets('the menu opens settings and a bad key shows the server error', (tester) async {
    final place = _place(
      'sf',
      'Criptas de San Francisco',
      'Imágenes de las criptas.',
    );
    final remote = _ScriptedRemote();
    final probe = _ScriptedProbe(
      deep: const ConnectionReport(ok: false, status: 401, detail: 'Invalid API key'),
      eleven: const ConnectionReport(ok: false, status: 401, detail: 'unauthorized'),
    );
    final chat = _chat(
      [place],
      visit: VisitContext()..updatePlace(place),
      remote: remote,
      connections: probe,
    );
    SharedPreferences.setMockInitialValues({});
    await _showChat(tester, chat);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-eleven-key')), findsNothing);
    expect(find.text('Pega aquí la clave de DeepSeek'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(GuideSettingsScreen), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-test-deepseek')));
    await tester.pumpAndSettle();
    expect(probe.deepCalls, 0);
    expect(find.textContaining('Falta la clave'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat-settings-deepseek')), 'clave-mala');
    await tester.tap(find.byKey(const Key('chat-test-deepseek')));
    await tester.pumpAndSettle();
    expect(probe.deepCalls, 1);
    expect(probe.lastDeepKey, 'clave-mala');
    expect(find.text('401 Invalid API key'), findsOneWidget);
    expect(find.text('Conectado'), findsNothing);

    probe.deep = const ConnectionReport(ok: true, status: 200);
    await tester.tap(find.byKey(const Key('chat-test-deepseek')));
    await tester.pumpAndSettle();
    expect(find.text('Conectado'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat-settings-eleven')), 'eleven-mala');
    await tester.enterText(find.byKey(const Key('chat-settings-voice')), 'voz-de-prueba-123456');
    await tester.tap(find.byKey(const Key('chat-test-eleven')));
    await tester.pumpAndSettle();
    expect(probe.elevenCalls, 1);
    expect(probe.lastElevenKey, 'eleven-mala');
    expect(chat.elevenVoiceId, 'voz-de-prueba-123456');
    expect(chat.elevenKey, 'eleven-mala');
    expect(find.text('401 unauthorized'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-mode-local')));
    await tester.pumpAndSettle();
    final calls = remote.calls;
    await tester.tap(find.byKey(const Key('chat-local-founded')));
    await tester.pumpAndSettle();
    expect(remote.calls, calls);
    expect(find.textContaining('Imágenes de las criptas.'), findsNothing);
    chat.dispose();
  });

  testWidgets('a compiled key hides its settings field', (tester) async {
    final probe = _ScriptedProbe(
      deep: const ConnectionReport(ok: false, status: 403, detail: 'forbidden'),
    );
    final chat = _chat(
      [],
      connections: probe,
      compiledKey: 'compiled-deep',
    );
    SharedPreferences.setMockInitialValues({});
    await _showChat(tester, chat);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-settings-deepseek')), findsNothing);
    expect(find.text('Esta clave viene de la compilación.'), findsOneWidget);
    expect(find.text('compiled-deep'), findsNothing);
    await tester.tap(find.byKey(const Key('chat-test-deepseek')));
    await tester.pumpAndSettle();
    expect(probe.lastDeepKey, 'compiled-deep');
    expect(find.text('403 forbidden'), findsOneWidget);
    expect(find.text('compiled-deep'), findsNothing);
    chat.dispose();
  });
}

ChatController _chat(
  List<ObjectModel> places, {
  VisitContext? visit,
  RemoteGuideAnswerService? remote,
  ChatAnswerMode mode = ChatAnswerMode.deepseek,
  GuideSecretStore? secrets,
  ConnectionChecker? connections,
  String compiledKey = '',
}) {
  final chat = ChatController(
    store: MemoryConversationStore(),
    knowledge: LocalKnowledgeSource(_FakeRepository(places)),
    answers: LocalGuideAnswerService(),
    remote: remote ?? _ScriptedRemote(),
    visit: visit ?? VisitContext(),
    secrets: secrets,
    connections: connections,
    compiledKey: compiledKey,
  );
  if (mode != ChatAnswerMode.local) {
    chat.setMode(mode, persist: false);
  }
  return chat;
}

Future<void> _showChat(
  WidgetTester tester,
  ChatController chat, {
  LocaleController? locale,
  double keyboard = 0,
}) {
  final localeController = locale ?? LocaleController();
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: localeController),
        ChangeNotifierProvider.value(value: chat),
      ],
      child: MaterialApp(
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en'), Locale('de')],
        home: const ChatScreen(key: ValueKey('scroll-chat')),
      ),
    ),
  );
}

Future<void> _ask(
  WidgetTester tester,
  ChatController chat,
  _HeldRemote remote,
  String question,
  String answer,
) async {
  final pending = chat.submit(question, languageCode: 'es', noDataText: 'sin datos');
  var opened = false;
  for (var i = 0; i < 10 && !opened; i++) {
    await tester.pump();
    final gate = remote.gate;
    if (gate != null && !gate.isCompleted) {
      gate.complete(answer);
      opened = true;
    }
  }
  expect(opened, isTrue);
  await tester.pump();
  await pending;
}

double _threadOffset(WidgetTester tester) => _threadPosition(tester).pixels;

double _threadExtent(WidgetTester tester) => _threadPosition(tester).maxScrollExtent;

ScrollPosition _threadPosition(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byKey(const Key('chat-thread')),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(finder).position;
}

class _HeldRemote extends RemoteGuideAnswerService {
  _HeldRemote() : super(apiKey: 'test', fallback: LocalGuideAnswerService());

  Completer<String>? gate;

  @override
  Future<String?> tryAsk({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
  }) {
    final pending = Completer<String>();
    gate = pending;
    return pending.future;
  }

  @override
  Future<String?> tryAskSpoken({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required void Function(String sentence) onSentence,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
    int dialogueLimit = RemoteGuideAnswerService.maxDialogueMessages,
  }) async {
    final text = await tryAsk(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      noDataText: noDataText,
      history: history,
      placeName: placeName,
      summary: summary,
    );
    if (text != null && text.trim().isNotEmpty) onSentence(text.trim());
    return text;
  }
}

class _ScriptedProbe implements ConnectionChecker {
  ConnectionReport deep;
  ConnectionReport eleven;
  int deepCalls = 0;
  int elevenCalls = 0;
  String lastDeepKey = '';
  String lastElevenKey = '';

  _ScriptedProbe({
    required this.deep,
    this.eleven = const ConnectionReport(ok: true, status: 200),
  });

  @override
  Future<ConnectionReport> deepSeek(String apiKey) async {
    deepCalls += 1;
    lastDeepKey = apiKey;
    return deep;
  }

  @override
  Future<ConnectionReport> elevenLabs(String apiKey) async {
    elevenCalls += 1;
    lastElevenKey = apiKey;
    return eleven;
  }
}

class _ScriptedRemote extends RemoteGuideAnswerService {
  _ScriptedRemote() : super(apiKey: 'test', fallback: LocalGuideAnswerService());

  int calls = 0;
  int lastLimit = 7;
  final List<List<KnowledgeSnippet>> seen = [];

  List<ChatMessage> lastHistory = const [];
  String lastPlace = '';
  String lastSummary = '';

  @override
  Future<String?> tryAsk({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
  }) async {
    calls += 1;
    seen.add(snippets);
    lastHistory = history;
    lastPlace = placeName;
    lastSummary = summary;
    return 'respuesta de la guia';
  }

  @override
  Future<String?> tryAskSpoken({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required void Function(String sentence) onSentence,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
    int dialogueLimit = RemoteGuideAnswerService.maxDialogueMessages,
  }) async {
    lastLimit = dialogueLimit;
    final text = await tryAsk(
      question: question,
      languageCode: languageCode,
      snippets: snippets,
      noDataText: noDataText,
      history: history,
      placeName: placeName,
      summary: summary,
    );
    if (text != null && text.trim().isNotEmpty) onSentence(text.trim());
    return text;
  }
}

class _ErrorRemote extends RemoteGuideAnswerService {
  _ErrorRemote(this.error) : super(apiKey: 'test', fallback: LocalGuideAnswerService());

  final Object error;

  @override
  Future<String?> tryAsk({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
  }) async {
    throw error;
  }

  @override
  Future<String?> tryAskSpoken({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required void Function(String sentence) onSentence,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
    int dialogueLimit = RemoteGuideAnswerService.maxDialogueMessages,
  }) async {
    throw error;
  }
}

class _OfflineRemote extends RemoteGuideAnswerService {
  _OfflineRemote() : super(apiKey: 'test', fallback: LocalGuideAnswerService());

  int calls = 0;

  @override
  Future<String?> tryAsk({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
  }) async {
    calls += 1;
    throw const SocketException('offline');
  }

  @override
  Future<String?> tryAskSpoken({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required void Function(String sentence) onSentence,
    List<ChatMessage> history = const [],
    String placeName = '',
    String summary = '',
    int dialogueLimit = RemoteGuideAnswerService.maxDialogueMessages,
  }) async {
    calls += 1;
    throw const SocketException('offline');
  }
}

String _facts(_ScriptedRemote remote) {
  return remote.seen.last.map((snippet) => '${snippet.title}\n${snippet.fact}').join('\n');
}

ObjectModel _place(
  String id,
  String name,
  String description, {
  String? openingHours,
  String? direccion,
  String cryptDescription = '',
  String? celular,
  int? yearFounded,
  Map<String, Map<String, String>> translations = const {},
}) {
  return ObjectModel(
    id: id,
    name: name,
    name2: name,
    description: description,
    cryptDescription: cryptDescription,
    imageUrl: '',
    imageUrl2: '',
    openingHours: openingHours,
    direccion: direccion,
    celular: celular,
    yearFounded: yearFounded,
    translations: translations,
  );
}

class _FakeRepository implements ContentRepository {
  final List<ObjectModel> places;

  _FakeRepository(this.places);

  @override
  Future<List<ObjectModel>> getPlaces() async => places;

  @override
  Future<ObjectModel?> findByCode(String code) async => null;

  @override
  Future<List<RecommendedModel>> getRecommended() async => [];

  @override
  Future<ObjectCarousel?> getCarousel() async => null;

  @override
  Future<void> savePendingComment(PendingComment comment) async {}
}

class _FakeEar implements ChatEar {
  ChatStatus? onStatus;
  void Function()? onError;
  ChatWords? onWords;
  ChatLevel? onLevel;
  String? localeId;
  int prepares = 0;
  int listens = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Future<bool> prepare({
    required ChatStatus onStatus,
    required void Function() onError,
  }) async {
    prepares += 1;
    this.onStatus = onStatus;
    this.onError = onError;
    return true;
  }

  SpeechListenOptions? options;

  @override
  Future<void> listen({
    required ChatWords onWords,
    required ChatLevel onLevel,
    required String localeId,
    SpeechListenOptions? options,
  }) async {
    listens += 1;
    this.onWords = onWords;
    this.onLevel = onLevel;
    this.localeId = localeId;
    this.options = options;
  }

  @override
  Future<void> stop() async {
    stops += 1;
    onStatus?.call('done');
  }

  @override
  Future<void> cancel() async {
    cancels += 1;
    onStatus?.call('done');
  }
}

class _FakeSpeaker implements ChatSpeaker {
  String? lastText;
  void Function()? pendingDone;

  @override
  Future<void> speak({
    required String text,
    required String languageCode,
    required void Function() onDone,
  }) async {
    lastText = text;
    pendingDone = onDone;
  }

  @override
  Future<void> stop() async {
    pendingDone = null;
  }

  void finish() {
    final done = pendingDone;
    pendingDone = null;
    done?.call();
  }
}
