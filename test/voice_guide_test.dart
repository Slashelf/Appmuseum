import 'dart:convert';
import 'dart:typed_data';

import 'package:app_guia_v1/chat/chat_voice.dart';
import 'package:app_guia_v1/chat/eleven_labs_speech.dart';
import 'package:app_guia_v1/chat/guide_narrator.dart';
import 'package:app_guia_v1/chat/spoken_sentences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sentences leave as soon as they close', () {
    final buffer = SpokenSentenceBuffer();
    expect(buffer.add('Fundado en '), isEmpty);
    expect(buffer.add('mil quinientos cuarenta y siete. '), ['Fundado en mil quinientos cuarenta y siete.']);
    expect(buffer.add('Luego sigue'), isEmpty);
    expect(buffer.flush(), 'Luego sigue');
  });

  test('elevenlabs asks for the fast model and hides the key', () {
    const secret = 'sk_test_secret';
    final payload = ElevenLabsSpeech.body('Hola.');
    expect(payload['model_id'], 'eleven_flash_v2_5');
    expect(payload['voice_settings'], containsPair('use_speaker_boost', false));
    expect(jsonEncode(payload), isNot(contains(secret)));
    expect(ElevenLabsSpeech.streamUri(ElevenLabsSpeech.voiceId).path, contains('/stream'));
    expect(ElevenLabsSpeech.streamUri(ElevenLabsSpeech.voiceId).query, contains('mp3_22050_32'));
    final headers = ElevenLabsSpeech.headers(secret);
    expect(headers['xi-api-key'], secret);
    expect(ElevenLabsSpeech.redacted(headers), isNot(contains(secret)));
    expect(voiceListenOptions('es_ES').pauseFor, const Duration(milliseconds: 1200));
    expect(chatListenOptions('es_ES').pauseFor, const Duration(seconds: 3));
  });

  test('a rejected voice falls back to the phone without an error', () async {
    final speaker = _MemorySpeaker();
    var fetches = 0;
    final narrator = GuideNarrator(
      fallback: speaker,
      fetch: (text, key, voice) async {
        fetches += 1;
        expect(key, 'sk_test_secret');
        expect(voice, ElevenLabsSpeech.voiceId);
        return NarrationFetch(status: 402, bytes: Uint8List(0));
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
    expect(fetches, 1);
    expect(speaker.lastText, 'Hola.');
    speaker.finish();
    await Future<void>.delayed(Duration.zero);
  });

  test('a missing voice key uses the phone and does not call elevenlabs', () async {
    final speaker = _MemorySpeaker();
    var fetches = 0;
    final narrator = GuideNarrator(
      fallback: speaker,
      fetch: (text, key, voice) async {
        fetches += 1;
        return NarrationFetch(status: 200, bytes: Uint8List.fromList([1]));
      },
    );
    narrator.enqueue(
      'Hola.',
      languageCode: 'es',
      apiKey: () => '',
      voiceId: () => ElevenLabsSpeech.voiceId,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 0);
    expect(speaker.lastText, 'Hola.');
    speaker.finish();
  });
}

class _MemorySpeaker implements ChatSpeaker {
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
