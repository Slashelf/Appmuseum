import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Silencio que cierra la escucha del chat de texto.
const chatSilencePause = Duration(seconds: 3);

/// Silencio de la pantalla Hablar. En Android el reconocedor lo aproxima.
const voiceSilencePause = Duration(milliseconds: 1200);

/// Si nadie habla, la pantalla Hablar deja de escuchar.
const voiceIdlePause = Duration(seconds: 20);

/// Tope para que el micrófono no quede abierto si el teléfono no detecta silencio.
const chatListenLimit = Duration(seconds: 60);

SpeechListenOptions chatListenOptions(String localeId) {
  return SpeechListenOptions(
    partialResults: true,
    cancelOnError: true,
    listenMode: ListenMode.dictation,
    pauseFor: chatSilencePause,
    listenFor: chatListenLimit,
    localeId: localeId,
  );
}

SpeechListenOptions voiceListenOptions(String localeId) {
  return SpeechListenOptions(
    partialResults: true,
    cancelOnError: true,
    listenMode: ListenMode.dictation,
    pauseFor: voiceSilencePause,
    listenFor: chatListenLimit,
    localeId: localeId,
  );
}

typedef ChatWords = void Function(String words, bool isFinal);
typedef ChatLevel = void Function(double level);
typedef ChatStatus = void Function(String status);

/// Escucha del chat. En pruebas se sustituye por un doble.
abstract class ChatEar {
  Future<bool> prepare({
    required ChatStatus onStatus,
    required void Function() onError,
  });

  Future<void> listen({
    required ChatWords onWords,
    required ChatLevel onLevel,
    required String localeId,
    SpeechListenOptions? options,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// Voz que lee una respuesta. En pruebas se sustituye por un doble.
abstract class ChatSpeaker {
  Future<void> speak({
    required String text,
    required String languageCode,
    required void Function() onDone,
  });

  Future<void> stop();
}

class DeviceChatEar implements ChatEar {
  DeviceChatEar([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  Future<bool> prepare({
    required ChatStatus onStatus,
    required void Function() onError,
  }) async {
    try {
      return await _speech.initialize(
        onStatus: onStatus,
        onError: (_) => onError(),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> listen({
    required ChatWords onWords,
    required ChatLevel onLevel,
    required String localeId,
    SpeechListenOptions? options,
  }) {
    return _speech.listen(
      onResult: (result) => onWords(result.recognizedWords, result.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: options ?? chatListenOptions(localeId),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

class DeviceChatSpeaker implements ChatSpeaker {
  FlutterTts? _voice;

  @override
  Future<void> speak({
    required String text,
    required String languageCode,
    required void Function() onDone,
  }) async {
    final voice = _voice ??= FlutterTts();
    await voice.setLanguage(_ttsLanguage(languageCode));
    await voice.setSpeechRate(0.45);
    voice.setCompletionHandler(onDone);
    voice.setCancelHandler(onDone);
    await voice.speak(text);
  }

  @override
  Future<void> stop() async {
    await _voice?.stop();
  }
}

String _ttsLanguage(String languageCode) {
  switch (languageCode) {
    case 'en':
      return 'en-US';
    case 'de':
      return 'de-DE';
    default:
      return 'es-ES';
  }
}

/// El reconocedor no usa la misma escala en todos los teléfonos.
double chatSoundLevel(double level) {
  if (level.isNaN) return 0;
  if (level < 0) return ((level + 50) / 50).clamp(0.0, 1.0);
  return (level / 10).clamp(0.0, 1.0);
}
