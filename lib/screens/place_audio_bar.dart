import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../core/theme/app_theme.dart';
import 'app_localizations.dart';

/// Archivo local esperado para un lugar.
///
/// Los dos puntos del identificador se escriben como guion porque un nombre
/// con «:» no puede guardarse en Windows. Ejemplo: assets/audio/OBJ005.mp3
/// o assets/audio/D5-E0-59-B6-6F-C8.mp3.
String placeAudioAsset(String placeId) {
  final safe = placeId.trim().replaceAll(':', '-');
  return 'assets/audio/$safe.mp3';
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

/// Si hay un mp3 local, lo reproduce. Si no, lee el texto guardado con la voz del teléfono.
/// No inventa audio ni llama a un servicio de voces.
class PlaceAudioBar extends StatefulWidget {
  final String placeId;
  final String spokenText;
  final String languageCode;

  const PlaceAudioBar({
    super.key,
    required this.placeId,
    required this.spokenText,
    required this.languageCode,
  });

  @override
  State<PlaceAudioBar> createState() => _PlaceAudioBarState();
}

class _PlaceAudioBarState extends State<PlaceAudioBar> {
  AudioPlayer? _player;
  FlutterTts? _voice;
  bool _ready = false;
  bool _checked = false;
  double _speechProgress = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final asset = placeAudioAsset(widget.placeId);
    try {
      await rootBundle.load(asset);
      final player = AudioPlayer();
      await player.setAsset(asset);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _ready = true;
        _checked = true;
      });
      return;
    } catch (_) {
      // No hay grabación. Se intenta la voz del teléfono.
    }

    final text = widget.spokenText.trim();
    if (text.isEmpty) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _checked = true;
      });
      return;
    }

    try {
      final voice = FlutterTts();
      final result = await voice.setLanguage(_ttsLanguage(widget.languageCode));
      final available = result == 1 || result == true || result == '1';
      if (!available) {
        if (!mounted) return;
        setState(() {
          _ready = false;
          _checked = true;
        });
        return;
      }
      await voice.setSpeechRate(0.45);
      voice.setCompletionHandler(() {
        if (!mounted) return;
        setState(() => _speechProgress = 1);
      });
      voice.setCancelHandler(() {
        if (!mounted) return;
        setState(() => _speechProgress = 0);
      });
      voice.setProgressHandler((String spoken, int start, int end, String word) {
        if (!mounted || spoken.isEmpty) return;
        setState(() => _speechProgress = (end / spoken.length).clamp(0.0, 1.0));
      });
      if (!mounted) return;
      setState(() {
        _voice = voice;
        _ready = true;
        _checked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _checked = true;
      });
    }
  }

  Future<void> _play() async {
    final player = _player;
    if (player != null) {
      await player.play();
      return;
    }
    final voice = _voice;
    final text = widget.spokenText.trim();
    if (voice == null || text.isEmpty) return;
    setState(() => _speechProgress = 0);
    await voice.speak(text);
  }

  Future<void> _pause() async {
    final player = _player;
    if (player != null) {
      await player.pause();
      return;
    }
    await _voice?.pause();
  }

  Future<void> _stop() async {
    final player = _player;
    if (player != null) {
      await player.stop();
      await player.seek(Duration.zero);
      return;
    }
    await _voice?.stop();
    if (!mounted) return;
    setState(() => _speechProgress = 0);
  }

  @override
  void dispose() {
    _player?.dispose();
    _voice?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final player = _player;
    final label = !_checked
        ? ''
        : (_player != null
            ? t.get('audioReady')
            : (_voice != null ? t.get('audioVoice') : t.get('audioUnavailable')));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: GuidePalette.fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GuidePalette.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _control(
                tooltip: t.get('audioPlay'),
                icon: Icons.play_arrow,
                enabled: _ready,
                onPressed: () => _play(),
              ),
              _control(
                tooltip: t.get('audioPause'),
                icon: Icons.pause,
                enabled: _ready,
                onPressed: () => _pause(),
              ),
              _control(
                tooltip: t.get('audioStop'),
                icon: Icons.stop,
                enabled: _ready,
                onPressed: () => _stop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppFonts.poppins(fontSize: 12, color: GuidePalette.muted),
                ),
              ),
            ],
          ),
          if (player != null)
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final total = player.duration ?? Duration.zero;
                final max = total.inMilliseconds <= 0 ? 1 : total.inMilliseconds;
                final value = (position.inMilliseconds / max).clamp(0.0, 1.0);
                return _bar(value);
              },
            )
          else
            _bar(_voice == null ? 0 : _speechProgress),
        ],
      ),
    );
  }

  Widget _bar(double value) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        color: GuidePalette.accent,
        backgroundColor: GuidePalette.surface,
      ),
    );
  }

  Widget _control({
    required String tooltip,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, color: enabled ? GuidePalette.accent : GuidePalette.muted),
    );
  }
}
