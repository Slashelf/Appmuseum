import 'dart:convert';

import 'package:app_guia_v1/chat/chat_faq.dart';
import 'package:app_guia_v1/chat/chat_message.dart';
import 'package:app_guia_v1/chat/knowledge_source.dart';
import 'package:app_guia_v1/chat/local_guide_answer_service.dart';
import 'package:app_guia_v1/chat/place_card.dart';
import 'package:app_guia_v1/chat/remote_guide_answer_service.dart';
import 'package:app_guia_v1/models/object_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deepseek is not called when the guide has no matching text', () async {
    final service = RemoteGuideAnswerService(
      apiKey: 'unused',
      fallback: LocalGuideAnswerService(),
    );
    final text = await service.answer(
      question: 'capital de francia',
      languageCode: 'es',
      snippets: const [],
      noDataText: 'sin datos',
    );
    expect(text, 'sin datos');
  });

  test('deepseek does not call the network when the key is missing', () async {
    final service = RemoteGuideAnswerService(
      apiKey: '',
      fallback: LocalGuideAnswerService(),
    );
    final text = await service.tryAsk(
      question: 'horario',
      languageCode: 'es',
      snippets: const [
        KnowledgeSnippet(
          id: 'sf',
          title: 'San Francisco',
          body: 'Horario de manana',
          fact: 'Horario de manana',
          focus: AnswerFocus.hours,
          score: 1,
        ),
      ],
      noDataText: 'sin datos',
    );
    expect(text, isNull);
  });

  test('the package sends the full card, the question and six earlier messages', () {
    final place = ObjectModel(
      id: 'sf',
      name: 'Convento de San Francisco',
      name2: 'Templo franciscano',
      description: 'Entierros bajo el altar mayor.',
      cryptDescription: 'Templo de piedra.',
      imageUrl: '',
      imageUrl2: '',
      openingHours: 'Lunes a viernes por la tarde',
      direccion: 'Calle Tarija',
      entranceFee: 'Ingreso libre',
      architecturalStyle: 'Barroco mestizo',
      historicalNotes: 'Se visita con guía.',
      celular: '12345679',
      yearFounded: 1700,
      yearCompleted: 1773,
      tourAvailable: true,
    );
    final card = PlaceCard.fromPlace(place, 'es');
    expect(card, contains('Exhibición: Convento de San Francisco'));
    expect(card, contains('Lugar que representa: Convento de San Francisco'));
    expect(card, contains('Qué muestran las imágenes o piezas: Entierros bajo el altar mayor.'));
    expect(card, contains('Otro nombre: Templo franciscano'));
    expect(card, contains('Templo franciscano'));
    expect(card, contains('Ingreso libre'));
    expect(card, contains('Barroco mestizo'));
    expect(card, contains('Visitas guiadas'));
    expect(card, isNot(contains('1773')));

    final withPhone = PlaceCard.fromPlace(
      ObjectModel(
        id: 'merced',
        name: 'La Merced',
        name2: 'La Merced',
        description: 'Cripta de benefactores.',
        cryptDescription: '',
        imageUrl: '',
        imageUrl2: '',
        celular: '70111222',
      ),
      'es',
    );
    expect(withPhone, contains('70111222'));

    final history = [
      for (var i = 0; i < 10; i++) ChatMessage.guide('respuesta $i'),
      const ChatMessage.visitor('¿quién fundó este lugar?'),
    ];
    final body = RemoteGuideAnswerService(
      apiKey: 'test',
      fallback: LocalGuideAnswerService(),
    ).buildBody(
      question: '¿quién fundó este lugar?',
      languageCode: 'es',
      snippets: [
        KnowledgeSnippet(
          id: 'sf',
          title: 'Convento de San Francisco',
          body: card,
          fact: card,
          focus: AnswerFocus.story,
          score: 1,
        ),
      ],
      history: history,
      placeName: 'Convento de San Francisco',
    );

    final encoded = jsonEncode(body);
    expect(body['temperature'], 0.7);
    expect(body['max_output_tokens'], 450);
    expect(body.containsKey('thinking'), isFalse);
    expect(body['model'], 'grok-4.20-0309-non-reasoning');
    final dialogue = body['input'] as List;
    expect(dialogue, hasLength(4));
    expect(dialogue.first['content'], 'respuesta 7');
    expect(dialogue.last['content'], '¿quién fundó este lugar?');
    final system = body['instructions'] as String;
    expect(system, contains('Casa Nacional de la Moneda'));
    expect(system, contains('personalidad aburrida'));
    expect(system, contains('Exhibición actual: Convento de San Francisco'));
    expect(system.split('Exhibición actual:').first, isNot(contains('Convento de San Francisco')));
    expect(system.split('Resumen de la visita:').first, isNot(contains('Entierros bajo el altar')));
    expect(system, contains('habla solo de ese objeto'));
    expect(system, contains('Exhibición actual'));
    expect(system, isNot(contains('El usuario está en')));
    expect(system, contains('Entierros bajo el altar mayor'));
    expect(system, contains('Templo de piedra'));
    expect(system, contains('Lunes a viernes por la tarde'));
    expect(system, contains('Calle Tarija'));
    expect(system, contains('2 o 3 frases como máximo'));
    expect(system, contains('4 a 6 frases'));
    expect(system, contains('en el idioma en que te habla el visitante'));
    expect(system, contains('Resumen de la visita:'));
    expect(system, contains('no lo inventes'));
    expect(system, isNot(contains('Narrador de museo')));
    expect(encoded, isNot(contains('respuesta 0')));
    expect(encoded, isNot(contains('yearFounded')));
    expect(encoded, isNot(contains('12345679')));
    expect(encoded, isNot(contains('1700')));
    expect(encoded, isNot(contains('1773')));
  });

  test('voice on adds the narrator and can keep only four turns', () {
    final service = RemoteGuideAnswerService(
      apiKey: 'test',
      fallback: LocalGuideAnswerService(),
    );
    final history = [
      for (var i = 0; i < 8; i++) ChatMessage.guide('respuesta $i'),
    ];
    final quiet = service.buildBody(
      question: '¿Cuándo se fundó?',
      languageCode: 'es',
      snippets: const [],
      history: history,
      placeName: 'Criptas de San Francisco',
    );
    final spoken = service.buildBody(
      question: '¿Cuándo se fundó?',
      languageCode: 'es',
      snippets: const [],
      history: history,
      placeName: 'Criptas de San Francisco',
      spoken: true,
      dialogueLimit: 4,
    );
    final quietSystem = quiet['instructions'] as String;
    final spokenSystem = spoken['instructions'] as String;
    expect(quietSystem, isNot(contains('Narrador de museo')));
    expect(spokenSystem, contains('Narrador de museo'));
    expect(spokenSystem, contains('Exhibición actual'));
    expect(spokenSystem, contains('2 o 3 frases como máximo'));
    expect(spokenSystem.startsWith(quietSystem), isTrue);
    expect(spoken['model'], 'grok-4.20-0309-non-reasoning');
    expect(spoken['max_output_tokens'], 300);
    expect(quiet['max_output_tokens'], 450);
    expect(quiet['temperature'], 0.7);
    expect(spoken.containsKey('thinking'), isFalse);
    expect(spoken.containsKey('stream'), isFalse);
    final dialogue = spoken['input'] as List;
    expect(dialogue, hasLength(4));
    expect(DeepSeekSse.delta('data: {"choices":[{"delta":{"content":"Hola. "}}]}'), 'Hola. ');
    expect(DeepSeekSse.delta('data: [DONE]'), isNull);

    final other = service.buildBody(
      question: '¿Cuándo se fundó?',
      languageCode: 'es',
      snippets: const [],
      placeName: 'Criptas de La Merced',
    );
    final otherSystem = other['instructions'] as String;
    expect(
      otherSystem.split('Resumen de la visita:').first,
      quietSystem.split('Resumen de la visita:').first,
    );
    expect(DeepSeekLog.credit(402, ''), isTrue);
    expect(
      DeepSeekLog.credit(400, '{"error":{"code":"insufficient_quota"}}'),
      isTrue,
    );
    expect(DeepSeekLog.credit(401, 'Unauthorized'), isFalse);
    expect(
      DeepSeekLog.safe('Bearer sk-testsecret boom', 'sk-testsecret'),
      isNot(contains('sk-testsecret')),
    );
  });

  test('portuguese is named after the cached prefix', () {
    final service = RemoteGuideAnswerService(
      apiKey: 'test',
      fallback: LocalGuideAnswerService(),
    );
    String system(String language, {bool spoken = false}) {
      final body = service.buildBody(
        question: 'quando',
        languageCode: language,
        snippets: const [],
        placeName: 'Criptas',
        spoken: spoken,
      );
      return body['instructions'] as String;
    }

    final spanish = system('es');
    final portuguese = system('pt');
    expect(
      portuguese.split('Resumen de la visita:').first,
      spanish.split('Resumen de la visita:').first,
    );
    expect(portuguese, contains('Idioma de esta respuesta: pt'));
    expect(spanish, contains('Idioma de esta respuesta: es'));
    expect(system('de'), contains('Idioma de esta respuesta: de'));
    expect(system('pt', spoken: true).startsWith(portuguese), isTrue);
    expect(RemoteGuideAnswerService.answerLanguage('pt_BR'), 'pt');
  });
}
