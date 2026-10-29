import 'package:audio_session/audio_session.dart';

/// Altavoz y foco para la narración. El uso "media" sale por el altavoz,
/// no por el auricular de una llamada.
class SpeechRoute {
  static const configuration = AudioSessionConfiguration.speech();
  static bool _ready = false;

  static Future<void> prepare() async {
    if (_ready) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(configuration);
      await session.setActive(true);
      _ready = true;
    } catch (_) {}
  }
}
