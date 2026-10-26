import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_voice.dart';
import '../chat/guide_narrator.dart';
import '../core/locale/locale_controller.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';

Future<bool> voiceNetworkReachable() async {
  try {
    final result = await InternetAddress.lookup('api.deepseek.com')
        .timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

enum VoicePhase { listening, thinking, speaking, paused }

/// Conversación por voz a pantalla completa. Usa la misma exhibición y el mismo chat.
class VoiceConversationScreen extends StatefulWidget {
  final ChatEar? ear;
  final ChatSpeaker? speaker;
  final Future<bool> Function()? online;
  final Future<void> Function(String sentence, String languageCode)? onSpeak;
  final Future<void> Function()? onStop;

  const VoiceConversationScreen({
    super.key,
    this.ear,
    this.speaker,
    this.online,
    this.onSpeak,
    this.onStop,
  });

  @override
  State<VoiceConversationScreen> createState() => _VoiceConversationScreenState();
}

class _VoiceConversationScreenState extends State<VoiceConversationScreen>
    with SingleTickerProviderStateMixin {
  ChatEar? _ownedEar;
  GuideNarrator? _narrator;
  late final AnimationController _pulse;
  Timer? _silence;
  Timer? _idle;
  VoicePhase _phase = VoicePhase.listening;
  bool _muted = false;
  bool _offline = false;
  bool _replyOpen = false;
  bool _starting = false;
  bool _ignoreEar = false;
  int _pendingClips = 0;
  int _playGen = 0;
  double _level = 0;
  String _heard = '';
  String _userLine = '';
  String _guideLine = '';

  ChatEar get _ear => widget.ear ?? (_ownedEar ??= DeviceChatEar());

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _silence?.cancel();
    _idle?.cancel();
    _pulse.dispose();
    _narrator?.stop();
    if (_ownedEar != null) {
      _ear.cancel();
    }
    super.dispose();
  }

  GuideNarrator _voice(ChatSpeaker speaker) {
    return _narrator ??= GuideNarrator(fallback: speaker);
  }

  Future<bool> _reach() {
    if (widget.online != null) return widget.online!();
    if (const bool.fromEnvironment('FLUTTER_TEST') || Platform.environment['FLUTTER_TEST'] == 'true') {
      return Future.value(true);
    }
    return voiceNetworkReachable();
  }

  Future<void> _open() async {
    final online = await _reach();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _offline = true;
        _phase = VoicePhase.paused;
      });
      return;
    }
    await _beginListen();
  }

  Future<void> _beginListen() async {
    if (!mounted || _muted || _offline || _starting) return;
    if (_phase == VoicePhase.listening && _heard.isEmpty && _idle != null && _pendingClips == 0) {
      return;
    }
    _starting = true;
    _silence?.cancel();
    _heard = '';
    _level = 0;
    _ignoreEar = true;
    try {
      await _ear.stop();
    } catch (_) {}
    _ignoreEar = false;
    if (!mounted || _muted) {
      _starting = false;
      return;
    }
    setState(() => _phase = VoicePhase.listening);
    final language = context.read<LocaleController>().locale.languageCode;
    final ready = await _ear.prepare(onStatus: _onStatus, onError: _onEarError);
    if (!mounted || _muted) {
      _starting = false;
      return;
    }
    if (!ready) {
      _starting = false;
      setState(() {
        _offline = false;
        _phase = VoicePhase.paused;
      });
      return;
    }
    try {
      await _ear.listen(
        onWords: _onWords,
        onLevel: _onLevel,
        localeId: _localeId(language),
        options: voiceListenOptions(_localeId(language)),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _phase = VoicePhase.paused);
      }
    }
    _starting = false;
    _armIdle();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(voiceIdlePause, () {
      if (!mounted || _phase != VoicePhase.listening || _heard.trim().isNotEmpty) return;
      _silence?.cancel();
      _ear.stop();
      setState(() => _phase = VoicePhase.paused);
    });
  }

  void _onWords(String words, bool isFinal) {
    if (!mounted || _phase != VoicePhase.listening || _muted) return;
    if (words.trim().isEmpty) return;
    _idle?.cancel();
    _heard = words;
    setState(() => _userLine = words);
    _silence?.cancel();
    _silence = Timer(voiceSilencePause, () {
      final text = _heard.trim();
      if (text.isEmpty || _phase != VoicePhase.listening) return;
      _sendTurn(text);
    });
  }

  void _onLevel(double level) {
    if (!mounted || _phase != VoicePhase.listening) return;
    setState(() => _level = chatSoundLevel(level));
  }

  void _onStatus(String status) {
    if (!mounted || _muted || _ignoreEar) return;
    if (status != 'done' && status != 'notListening') return;
    if (_phase != VoicePhase.listening) return;
    final text = _heard.trim();
    if (text.isEmpty) return;
    _silence?.cancel();
    _sendTurn(text);
  }

  void _onEarError() {
    if (!mounted) return;
    _silence?.cancel();
    _idle?.cancel();
    setState(() => _phase = VoicePhase.paused);
  }

  Future<void> _sendTurn(String text) async {
    if (_replyOpen || _phase == VoicePhase.thinking || _phase == VoicePhase.speaking) return;
    _silence?.cancel();
    _idle?.cancel();
    _heard = '';
    _replyOpen = true;
    final generation = ++_playGen;
    setState(() {
      _phase = VoicePhase.thinking;
      _userLine = text;
      _guideLine = '';
      _offline = false;
    });
    try {
      await _ear.stop();
    } catch (_) {}
    if (!mounted || generation != _playGen) {
      _replyOpen = false;
      return;
    }
    final online = await _reach();
    if (!mounted || generation != _playGen) {
      _replyOpen = false;
      return;
    }
    if (!online) {
      _replyOpen = false;
      setState(() {
        _offline = true;
        _phase = VoicePhase.paused;
      });
      return;
    }
    final chat = context.read<ChatController>();
    final language = context.read<LocaleController>().locale.languageCode;
    final t = AppLocalizations.of(context);
    await chat.submit(
      text,
      languageCode: language,
      noDataText: t.get('chatNoData'),
      aiUnavailableText: t.get('aiUnavailable'),
      spoken: true,
      fromVoice: true,
      dialogueLimit: 4,
      onSentence: (sentence) {
        if (!mounted || generation != _playGen) return;
        _pendingClips++;
        setState(() {
          _phase = VoicePhase.speaking;
          _guideLine = _guideLine.isEmpty ? sentence : '$_guideLine $sentence';
        });
        _play(sentence, language, generation);
      },
    );
    _replyOpen = false;
    if (!mounted || generation != _playGen) return;
    if (chat.tookOffline) {
      setState(() {
        _offline = true;
        _phase = VoicePhase.paused;
      });
      return;
    }
    if (_pendingClips == 0) _afterSpeech(generation);
  }

  Future<void> _play(String sentence, String language, int generation) async {
    try {
      if (widget.onSpeak != null) {
        await widget.onSpeak!(sentence, language);
      } else {
        final speaker = widget.speaker ?? DeviceChatSpeaker();
        _voice(speaker).onIdle = () {
          _pendingClips = 0;
          _afterSpeech(generation);
        };
        _voice(speaker).enqueue(
          sentence,
          languageCode: language,
          apiKey: () => context.read<ChatController>().elevenKey,
          voiceId: () => context.read<ChatController>().elevenVoiceId,
        );
        return;
      }
    } catch (_) {}
    if (!mounted || generation != _playGen) return;
    _pendingClips = math.max(0, _pendingClips - 1);
    if (_pendingClips == 0 && !_replyOpen) _afterSpeech(generation);
  }

  void _afterSpeech(int generation) {
    if (!mounted || generation != _playGen || _replyOpen || _muted || _offline) return;
    if (_pendingClips > 0) return;
    if (_narrator != null && _narrator!.busy) return;
    if (_phase == VoicePhase.paused) return;
    _beginListen();
  }

  Future<void> _interrupt() async {
    _playGen++;
    _pendingClips = 0;
    _replyOpen = false;
    _silence?.cancel();
    _guideLine = _guideLine;
    try {
      await widget.onStop?.call();
    } catch (_) {}
    await _narrator?.stop();
    if (!mounted) return;
    await _beginListen();
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    if (_muted) {
      _silence?.cancel();
      _idle?.cancel();
      try {
        await _ear.stop();
      } catch (_) {}
    } else if (_phase != VoicePhase.speaking && _phase != VoicePhase.thinking) {
      await _beginListen();
    }
    if (mounted) setState(() {});
  }

  Future<void> _exit() async {
    _playGen++;
    _silence?.cancel();
    _idle?.cancel();
    try {
      await widget.onStop?.call();
    } catch (_) {}
    await _narrator?.stop();
    try {
      await _ear.cancel();
    } catch (_) {}
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _resumeFromPause() async {
    final online = await _reach();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _offline = true;
        _phase = VoicePhase.paused;
      });
      return;
    }
    setState(() => _offline = false);
    _muted = false;
    await _beginListen();
  }

  String _localeId(String language) {
    switch (language) {
      case 'en':
        return 'en_US';
      case 'de':
        return 'de_DE';
      default:
        return 'es_ES';
    }
  }

  String _statusLabel(AppLocalizations t) {
    switch (_phase) {
      case VoicePhase.thinking:
        return t.get('voiceStatusThinking');
      case VoicePhase.speaking:
        return t.get('voiceStatusSpeaking');
      case VoicePhase.paused:
        return _offline ? '' : t.get('voiceTapToContinue');
      case VoicePhase.listening:
        return t.get('voiceStatusListening');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final language = context.watch<LocaleController>().locale.languageCode;
    final place = context.watch<ChatController>().visit.place?.localized(language);
    final placeName = (place?.name.trim().isNotEmpty ?? false) ? place!.name : place?.name2;
    final status = _statusLabel(t);

    return Scaffold(
      backgroundColor: GuidePalette.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  IconButton(
                    key: const Key('voice-exit'),
                    tooltip: t.get('voiceExit'),
                    onPressed: _exit,
                    icon: const Icon(Icons.close, color: GuidePalette.ink),
                  ),
                ],
              ),
              if (placeName != null && placeName.trim().isNotEmpty)
                Text(
                  t.get('chatHere').replaceAll('{name}', placeName),
                  textAlign: TextAlign.center,
                  style: AppFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GuidePalette.accent,
                  ),
                ),
              if (_offline)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    t.get('voiceOffline'),
                    key: const Key('voice-offline'),
                    textAlign: TextAlign.center,
                    style: AppFonts.poppins(fontSize: 14, color: GuidePalette.ink, height: 1.35),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                key: const Key('voice-sphere'),
                onTap: () {
                  if (_phase == VoicePhase.paused) {
                    _resumeFromPause();
                    return;
                  }
                  if (_phase == VoicePhase.speaking || _phase == VoicePhase.thinking) {
                    _interrupt();
                  }
                },
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final pulse = _phase == VoicePhase.listening ? _level : _pulse.value;
                    return CustomPaint(
                      painter: _SpherePainter(
                        pulse: pulse,
                        speaking: _phase == VoicePhase.speaking || _phase == VoicePhase.thinking,
                      ),
                      child: const SizedBox(width: 220, height: 220),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              if (status.isNotEmpty)
                Text(
                  status,
                  key: const Key('voice-status'),
                  style: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
                ),
              if (_phase == VoicePhase.paused && !_offline)
                TextButton(
                  key: const Key('voice-continue'),
                  onPressed: _resumeFromPause,
                  child: Text(t.get('voiceTapToContinue')),
                ),
              const Spacer(),
              if (_userLine.trim().isNotEmpty)
                Text(
                  _userLine,
                  key: const Key('voice-user-line'),
                  textAlign: TextAlign.center,
                  style: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
                ),
              if (_guideLine.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _guideLine,
                    key: const Key('voice-guide-line'),
                    textAlign: TextAlign.center,
                    style: AppFonts.poppins(fontSize: 14, color: GuidePalette.ink, height: 1.35),
                  ),
                ),
              const SizedBox(height: 12),
              IconButton(
                key: const Key('voice-mute'),
                tooltip: _muted ? t.get('voiceUnmute') : t.get('voiceMute'),
                onPressed: _toggleMute,
                icon: Icon(
                  _muted ? Icons.mic_off : Icons.mic,
                  color: _muted ? GuidePalette.muted : GuidePalette.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpherePainter extends CustomPainter {
  final double pulse;
  final bool speaking;

  const _SpherePainter({required this.pulse, required this.speaking});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * (0.28 + pulse.clamp(0.0, 1.0) * 0.08);
    final glow = Paint()
      ..color = GuidePalette.accent.withValues(alpha: speaking ? 0.28 : 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, radius + 16, glow);
    final fill = Paint()..color = GuidePalette.accent;
    canvas.drawCircle(center, radius, fill);
    final highlight = Paint()..color = const Color(0x66FFF8E8);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.28, center.dy - radius * 0.32),
      radius * 0.22,
      highlight,
    );
    if (speaking) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GuidePalette.ink.withValues(alpha: 0.35);
      canvas.drawCircle(center, radius + 10 + math.sin(pulse * math.pi) * 6, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _SpherePainter oldDelegate) {
    return oldDelegate.pulse != pulse || oldDelegate.speaking != speaking;
  }
}
