import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_guia_v1/chat/chat_controller.dart';
import 'package:app_guia_v1/chat/chat_faq.dart';
import 'package:app_guia_v1/chat/chat_message.dart';
import 'package:app_guia_v1/chat/chat_voice.dart';
import 'package:app_guia_v1/chat/conversation_store.dart';
import 'package:app_guia_v1/chat/xai_speech.dart';
import 'package:app_guia_v1/chat/xai_realtime.dart';

import 'package:app_guia_v1/chat/guide_narrator.dart';
import 'package:app_guia_v1/chat/knowledge_source.dart';
import 'package:app_guia_v1/chat/local_guide_answer_service.dart';
import 'package:app_guia_v1/chat/remote_guide_answer_service.dart';
import 'package:app_guia_v1/chat/spanish_narrator.dart';
import 'package:app_guia_v1/chat/speech_route.dart';
import 'package:app_guia_v1/chat/voice_turn.dart';
import 'package:app_guia_v1/chat/spoken_sentences.dart';
import 'package:app_guia_v1/chat/visit_context.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the voice agent sends ara or leo, the guide instructions, and hides the key', () {
    const secret = 'sk-testsecret';
    final woman = XaiRealtime.sessionUpdate(
      instructions: 'Eres el guía. personalidad aburrida.',
      voice: 'ara',
      languageCode: 'es',
    );
    final session = woman['session'] as Map;
    expect(XaiRealtime.endpoint.toString(), 'wss://api.x.ai/v1/realtime?model=grok-voice-latest');
    expect(session['voice'], 'ara');
    expect(session['instructions'], contains('personalidad aburrida'));
    expect(session['instructions'], contains(ChatFaq.jokeOwes));
    expect(session['instructions'], contains(ChatFaq.noExhibitionNow));
    expect((session['turn_detection'] as Map)['type'], 'server_vad');
    expect((session['reasoning'] as Map)['effort'], 'none');
    final audio = session['audio'] as Map;
    expect(((audio['input'] as Map)['format'] as Map)['rate'], 24000);
    expect(((audio['input'] as Map)['transcription'] as Map)['language_hint'], 'es-MX');
    expect(XaiRealtime.sessionUpdate(instructions: 'x', voice: 'leo', languageCode: 'en')['session'], isA<Map>());
    final man = XaiRealtime.sessionUpdate(instructions: 'x', voice: 'leo', languageCode: 'en')['session'] as Map;
    expect(man['voice'], 'leo');
    expect(((man['audio'] as Map)['input'] as Map)['transcription'], {'language_hint': 'en'});
    expect(XaiRealtime.languageHint('de'), 'de');
    expect(XaiRealtime.languageHint('pt'), 'pt-BR');
    expect(XaiRealtime.voiceId('otra'), 'ara');

    final spoken = XaiRealtime.say('Veo que llegaste.', 'es');
    final item = spoken.first['item'] as Map;
    final content = (item['content'] as List).first as Map;
    expect(content['text'], contains('Veo que llegaste.'));
    expect(content['text'], contains('Di exactamente'));
    expect(spoken.last['type'], 'response.create');
    expect(XaiRealtime.ask('Cuéntame esta exhibición.').first['item'], isA<Map>());
    expect(XaiRealtime.cancel()['type'], 'response.cancel');
    final payload = jsonEncode(woman);
    expect(payload, isNot(contains(secret)));

    final notice = XaiRealtime.interpret({
      'type': 'error',
      'error': {'code': 'invalid_api_key', 'message': 'Incorrect API key $secret'},
    }, secret: secret);
    expect(notice.kind, XaiVoiceNoticeKind.failed);
    expect(notice.failure!.status, 401);
    expect(notice.failure!.detail, isNot(contains(secret)));
    expect(
      XaiRealtime.interpret({
        'type': 'error',
        'error': {
          'code': 'response_cancel_not_active',
          'message': 'Cancellation failed: no active response',
        },
      }).kind,
      XaiVoiceNoticeKind.ignore,
    );
    expect(
      XaiRealtime.interpret({
        'type': 'error',
        'error': {'message': 'no active response'},
      }).kind,
      XaiVoiceNoticeKind.ignore,
    );
    expect(XaiRealtime.benignCancel('response interrupted'), isTrue);
    expect(
      XaiRealtime.interpret({
        'type': 'response.output_audio.delta',
        'delta': base64Encode(Uint8List.fromList([1, 0])),
      }).kind,
      XaiVoiceNoticeKind.guideAudio,
    );
    expect(
      XaiRealtime.interpret({'type': 'response.audio.delta', 'delta': base64Encode(Uint8List.fromList([2, 0]))}).audio,
      isNotNull,
    );
    expect(XaiRealtime.statusOf('HTTP status code: 429'), 429);
    expect(
      XaiVoiceFailure.from(const SocketException('offline'), secret).offline,
      isTrue,
    );
    expect(
      XaiVoiceFailure.from(
        WebSocketException('was not upgraded, HTTP status code: 403'),
        secret,
      ).status,
      403,
    );
  });

  test('a short hello stays open until the rest of the sentence arrives', () {
    final turn = VoiceTurn();
    turn.hear('hola');
    expect(turn.text, 'hola');
    turn.engineStopped();
    expect(turn.text, 'hola');
    turn.hear('cuando se fundo');
    expect(turn.text, 'hola cuando se fundo');
    turn.hear('hola cuando se fundo la iglesia');
    expect(turn.text, 'hola cuando se fundo la iglesia');
    expect(turn.noteError(), isTrue);
    expect(turn.noteError(), isTrue);
    expect(turn.noteError(), isFalse);
    turn.hear('sigo');
    expect(turn.failures, 0);
    turn.reset();
    expect(turn.isEmpty, isTrue);
    expect(VoiceTurn.endpoint, const Duration(milliseconds: 2400));
  });

  test('sentences leave as soon as they close', () {
    final buffer = SpokenSentenceBuffer();
    expect(buffer.add('Fundado en '), isEmpty);
    expect(buffer.add('mil quinientos cuarenta y siete. '), ['Fundado en mil quinientos cuarenta y siete.']);
    expect(buffer.add('Luego sigue'), isEmpty);
    expect(buffer.flush(), 'Luego sigue');
  });

  test('xai tts sends text, voice and language and hides the key', () {
    const secret = 'sk_test_secret';
    final payload = XaiSpeech.body(
      'Segunda.',
      voiceId: 'ara',
      languageCode: 'pt',
    );
    expect(payload['text'], 'Segunda.');
    expect(payload['voice_id'], 'ara');
    expect(payload['language'], 'es-MX');
    expect(jsonEncode(payload), isNot(contains(secret)));
    expect(XaiSpeech.body('Hola.', voiceId: 'leo', languageCode: 'en')['language'], 'en');
    expect(XaiSpeech.body('Hola.', voiceId: 'ara', languageCode: 'de')['language'], 'de');
    expect(XaiSpeech.endpoint.host, 'api.x.ai');
    expect(XaiSpeech.endpoint.path, '/v1/tts');
    expect(GuideNarrator.usefulAudioLimit, const Duration(seconds: 8));
    final headers = XaiSpeech.headers(secret);
    expect(headers['Authorization'], 'Bearer $secret');
    expect(XaiSpeech.redacted(headers), isNot(contains(secret)));
    expect(voiceListenOptions('es_ES').pauseFor, chatListenLimit);
    expect(voiceListenOptions('es_ES').cancelOnError, isFalse);
    expect(chatListenOptions('es_ES').pauseFor, const Duration(seconds: 3));
    expect(chatListenOptions('es_ES').cancelOnError, isTrue);
    expect(ttsLanguage('pt'), 'pt-BR');
    expect(ttsLanguage('en'), 'en-US');
    expect(ttsLanguage('de'), 'de-DE');
  });

  test('a rejected voice falls back to the phone and keeps the reason', () async {
    final speaker = _MemorySpeaker();
    var fetches = 0;
    final narrator = GuideNarrator(
      fallback: speaker,
      fetch: (request) async {
        fetches += 1;
        expect(request.apiKey, 'sk_test_secret');
        expect(request.voiceId, 'voz-es');
        expect(jsonEncode(request.apiKey), isNot(contains('Daniel')));
        return NarrationFetch(status: 402, detail: 'sk_test_secret insufficient');
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 1);
    expect(speaker.lastText, 'Hola.');
    expect(speaker.lastLanguage, 'es');
    expect(narrator.lastPhoneReason, contains('402'));
    expect(narrator.lastPhoneReason, isNot(contains('sk_test_secret')));
  });

  test('an empty voice id does not call elevenlabs or reuse an english default', () async {
    final speaker = _MemorySpeaker();
    var fetches = 0;
    final narrator = GuideNarrator(
      fallback: speaker,
      fetch: (request) async {
        fetches += 1;
        return NarrationFetch(status: 200, bytes: Uint8List.fromList([1]));
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => '',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 0);
    expect(speaker.lastText, 'Hola.');
    expect(narrator.lastPhoneReason, isNull);
  });

  test('a missing voice key uses the phone and does not call elevenlabs', () async {
    final speaker = _MemorySpeaker();
    var fetches = 0;
    final narrator = GuideNarrator(
      fallback: speaker,
      fetch: (request) async {
        fetches += 1;
        return NarrationFetch(status: 200, bytes: Uint8List.fromList([1]));
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => '',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 0);
    expect(speaker.lastText, 'Hola.');
  });

  test('the next sentence of the same reply sends previous_text and pt', () async {
    final speaker = _MemorySpeaker();
    final seen = <NarrationRequest>[];
    final narrator = GuideNarrator(
      fallback: speaker,
      onUsefulAudio: (_) {},
      fetch: (request) async {
        seen.add(request);
        final payload = XaiSpeech.body(
          request.text,
          voiceId: request.voiceId,
          languageCode: request.languageCode,
        );
        expect(payload['voice_id'], 'voz-es');
        expect(payload['language'], 'es-MX');
        return NarrationFetch(status: 200, bytes: Uint8List.fromList([9]));
      },
    );
    narrator.enqueue(
      'Primera frase.',
      languageCode: 'pt',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    narrator.enqueue(
      'Segunda frase.',
      languageCode: 'pt',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(2));
    expect(seen.first.previousText, isNull);
    expect(seen.last.previousText, 'Primera frase.');
    expect(seen.last.languageCode, 'pt');
    narrator.beginReply();
    narrator.enqueue(
      'Otra respuesta.',
      languageCode: 'pt',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    expect(seen.last.previousText, isNull);
    expect(seen.last.text, 'Otra respuesta.');
  });

  test('no useful audio within the limit uses the phone', () async {
    final speaker = _MemorySpeaker();
    final audio = StreamController<List<int>>();
    final narrator = GuideNarrator(
      fallback: speaker,
      usefulAudioWait: const Duration(milliseconds: 15),
      fetch: (request) async {
        return NarrationFetch(status: 200, audio: audio.stream);
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(speaker.lastText, 'Hola.');
    expect(narrator.lastPhoneReason, contains('sin audio'));
    await audio.close();
  });

  test('the first chunk is enough to start', () async {
    final speaker = _MemorySpeaker();
    Uint8List? heard;
    final narrator = GuideNarrator(
      fallback: speaker,
      onUsefulAudio: (bytes) => heard = bytes,
      fetch: (request) async {
        return NarrationFetch(
          status: 200,
          audio: Stream<List<int>>.value(const [1, 2, 3, 4]),
        );
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(heard, isNotNull);
    expect(heard, isNotEmpty);
    expect(speaker.lastText, isNull);
  });

  test('a premade spanish narrator wins over an english one', () {
    expect(SpanishNarratorLookup.voicesUri.path, '/v1/tts/voices');
    expect(SpanishNarratorLookup.voicesUri.host, 'api.x.ai');
    final onlyEnglish = SpanishNarrator.choose([
      {
        'voice_id': 'onwK4e9ZLuTAKqWW03F9',
        'name': 'Daniel',
        'category': 'premade',
        'labels': {
          'accent': 'british',
          'description': 'calm',
          'gender': 'male',
          'use_case': 'narrative_story',
        },
        'verified_languages': [
          {'language': 'en'},
        ],
      },
    ]);
    expect(onlyEnglish, isNull);
    final picked = SpanishNarrator.choose([
      {
        'voice_id': 'onwK4e9ZLuTAKqWW03F9',
        'name': 'Daniel',
        'category': 'premade',
        'labels': {
          'accent': 'british',
          'gender': 'male',
          'use_case': 'narrative_story',
        },
        'verified_languages': [
          {'language': 'en'},
        ],
      },
      {
        'voice_id': 'clon-es',
        'name': 'Clon',
        'category': 'cloned',
        'labels': {'accent': 'peninsular', 'description': 'warm', 'use_case': 'narrative_story'},
        'verified_languages': [
          {'language': 'es'},
        ],
      },
      {
        'voice_id': 'es-fria',
        'name': 'Ana',
        'category': 'premade',
        'labels': {
          'accent': 'peninsular',
          'gender': 'female',
          'use_case': 'conversational',
          'description': 'clear',
        },
        'verified_languages': [
          {'language': 'es'},
        ],
      },
      {
        'voice_id': 'es-calida',
        'name': 'Mateo',
        'category': 'premade',
        'labels': {
          'accent': 'peninsular',
          'gender': 'male',
          'use_case': 'narrative_story',
          'description': 'warm',
        },
        'verified_languages': [
          {'language': 'es'},
        ],
      },
    ]);
    expect(picked, 'es-calida');
  });

  test('portuguese mic asks the model in pt and can store a listed voice', () async {
    SharedPreferences.setMockInitialValues({});
    final remote = _LangRemote();
    var lookups = 0;
    final chat = ChatController(
      store: MemoryConversationStore(),
      knowledge: _EmptyKnowledge(),
      answers: LocalGuideAnswerService(),
      remote: remote,
      visit: VisitContext(),
      voices: _FixedVoices(() {
        lookups += 1;
        return 'es-calida';
      }),
    );
    await chat.setMode(ChatAnswerMode.deepseek, persist: false);
    await chat.setMicLanguage('pt');
    expect(chat.replyLanguage('de'), 'pt');
    expect(chat.earLocale('de'), 'pt_BR');
    await chat.submit('quando', languageCode: 'de', noDataText: 'sin');
    expect(remote.asked, 'pt');
    await chat.setMicLanguage('auto');
    expect(chat.replyLanguage('de'), 'de');
    expect(chat.earLocale('en'), 'en_US');
    chat.updateVoiceId('leo');
    expect(await chat.ensureNarratorVoice(), 'leo');
    expect(chat.guideVoice, 'leo');
    expect(lookups, 0);
    chat.updateVoiceId('ya-elegida');
    expect(await chat.ensureNarratorVoice(), 'ara');
    expect(lookups, 0);
    chat.updateVoiceId('');
    expect(chat.guideVoice, 'ara');

    final missed = ChatController(
      store: MemoryConversationStore(),
      knowledge: _EmptyKnowledge(),
      answers: LocalGuideAnswerService(),
      remote: remote,
      visit: VisitContext(),
    );
    expect(await missed.ensureNarratorVoice(), 'ara');
    expect(missed.guideVoice, 'ara');
  });

  test('speech route uses the loudspeaker and takes focus', () {
    final route = SpeechRoute.configuration;
    expect(route.androidAudioAttributes?.contentType, AndroidAudioContentType.speech);
    expect(route.androidAudioAttributes?.usage, AndroidAudioUsage.media);
    expect(route.androidAudioFocusGainType, AndroidAudioFocusGainType.gain);
    expect(route.androidWillPauseWhenDucked, isTrue);
  });

  test('a download that finishes after stop does not play', () async {
    final gate = Completer<NarrationFetch>();
    var opens = 0;
    var heard = 0;
    final narrator = GuideNarrator(
      fallback: _MemorySpeaker(),
      fetch: (_) => gate.future,
      onBytes: (_) => heard += 1,
      openPlayback: () {
        opens += 1;
        return _FakeClip();
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await narrator.stop();
    gate.complete(NarrationFetch(status: 200, bytes: Uint8List.fromList([1, 2, 3, 4])));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(opens, 0);
    expect(heard, 0);
  });

  test('disposing the narrator releases the player', () async {
    final fake = _FakeClip();
    var opens = 0;
    var routes = 0;
    final narrator = GuideNarrator(
      fallback: _MemorySpeaker(),
      fetch: (_) async => NarrationFetch(status: 200, bytes: Uint8List.fromList([1, 2, 3, 4])),
      openPlayback: () {
        opens += 1;
        return fake;
      },
      prepareRoute: () async {
        routes += 1;
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fake.plays, 1);
    expect(routes, 1);
    expect(opens, 1);
    await narrator.dispose();
    expect(fake.closed, isTrue);
    expect(narrator.playerReleased, isTrue);
    narrator.enqueue(
      'Otra.',
      languageCode: 'es',
      apiKey: () => 'sk_test_secret',
      voiceId: () => 'voz-es',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fake.plays, 1);
    expect(opens, 1);
  });

  test('a second read does not steal the finish notice', () async {
    final engine = _FakeTts();
    final speaker = DeviceChatSpeaker(engine: engine, prepareRoute: () async {});
    var first = 0;
    var second = 0;
    await speaker.speak(text: 'uno', languageCode: 'es', onDone: () => first += 1);
    await speaker.speak(text: 'dos', languageCode: 'es', onDone: () => second += 1);
    expect(engine.binds, 1);
    expect(first, 1);
    expect(second, 0);
    engine.finish?.call();
    expect(second, 1);
    expect(first, 1);
  });

  test('stopping the phone voice finishes the waiter once', () async {
    final engine = _FakeTts();
    final speaker = DeviceChatSpeaker(engine: engine, prepareRoute: () async {});
    var done = 0;
    await speaker.speak(text: 'uno', languageCode: 'es', onDone: () => done += 1);
    expect(done, 0);
    await speaker.stop();
    expect(done, 1);
    await speaker.stop();
    expect(done, 1);
  });
}

class _FakeClip implements ClipPlayback {
  int plays = 0;
  bool closed = false;

  @override
  Future<void> load(StreamAudioSource source) async {}

  @override
  Future<void> play() async {
    plays += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _FakeTts implements TtsEngine {
  int binds = 0;
  void Function()? finish;
  String spoken = '';

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  void bindFinish(void Function() finish) {
    binds += 1;
    this.finish = finish;
  }

  @override
  Future<void> speak(String text) async {
    if (spoken.isNotEmpty) finish?.call();
    spoken = text;
  }

  @override
  Future<void> stop() async {
    finish?.call();
  }
}

class _MemorySpeaker implements ChatSpeaker {
  String? lastText;
  String? lastLanguage;

  @override
  Future<void> speak({
    required String text,
    required String languageCode,
    required void Function() onDone,
  }) async {
    lastText = text;
    lastLanguage = languageCode;
    onDone();
  }

  @override
  Future<void> stop() async {}
}

class _EmptyKnowledge implements KnowledgeSource {
  @override
  Future<List<KnowledgeSnippet>> search({
    required String question,
    required String languageCode,
    String? currentPlaceId,
  }) async {
    return const [];
  }
}

class _LangRemote extends RemoteGuideAnswerService {
  _LangRemote() : super(apiKey: 'test', fallback: LocalGuideAnswerService());

  String? asked;

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
    asked = languageCode;
    return 'Olá.';
  }
}

class _FixedVoices implements NarratorVoiceSource {
  _FixedVoices(this._pick);

  final String? Function() _pick;

  @override
  Future<String?> pick(String apiKey) async {
    expect(apiKey, 'sk_test_secret');
    return _pick();
  }

  @override
  Future<String?> resolve(String apiKey, String currentId) {
    if (currentId.trim().isNotEmpty) return Future.value(currentId.trim());
    return pick(apiKey);
  }
}
