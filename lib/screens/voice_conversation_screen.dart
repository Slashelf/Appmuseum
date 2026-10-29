import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_voice.dart';
import '../chat/guide_narrator.dart';
import '../chat/voice_turn.dart';
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
  String _userLine = '';
  String _guideLine = '';
  bool _phoneVoice = false;
  final VoiceTurn _turn = VoiceTurn();
  int _emptyStops = 0;
  int _listenGen = 0;

  ChatEar get _ear => widget.ear ?? (_ownedEar ??= DeviceChatEar());

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _silence?.cancel();
    _idle?.cancel();
    _pulse.dispose();
    final narrator = _narrator;
    _narrator = null;
    if (narrator != null) unawaited(narrator.dispose());
    if (_ownedEar != null) {
      _ear.cancel();
    }
    super.dispose();
  }

  GuideNarrator _voice(ChatSpeaker speaker) {
    final narrator = _narrator ??= GuideNarrator(fallback: speaker);
    narrator.onPhoneVoice = (_) {
      if (!mounted) return;
      setState(() => _phoneVoice = true);
    };
    narrator.onRemoteVoice = () {
      if (!mounted || !_phoneVoice) return;
      setState(() => _phoneVoice = false);
    };
    return narrator;
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

  Future<void> _beginListen({bool keepWords = false}) async {
    if (!mounted || _muted || _offline) return;
    if (!keepWords &&
        _phase == VoicePhase.listening &&
        _turn.isEmpty &&
        _idle != null &&
        _pendingClips == 0 &&
        !_starting) {
      return;
    }
    final generation = ++_listenGen;
    _starting = true;
    if (!keepWords) {
      _silence?.cancel();
      _turn.reset();
      _level = 0;
      _emptyStops = 0;
    }
    _ignoreEar = true;
    try {
      await _ear.stop();
    } catch (_) {}
    _ignoreEar = false;
    if (!mounted || _muted || generation != _listenGen) {
      if (generation == _listenGen) _starting = false;
      return;
    }
    setState(() => _phase = VoicePhase.listening);
    final language = context.read<LocaleController>().locale.languageCode;
    final ready = await _ear.prepare(onStatus: _onStatus, onError: _onEarError);
    if (!mounted || _muted || generation != _listenGen) {
      if (generation == _listenGen) _starting = false;
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
    _starting = false;
    try {
      await _ear.listen(
        onWords: _onWords,
        onLevel: _onLevel,
        localeId: _localeId(language),
        options: voiceListenOptions(_localeId(language)),
      );
    } catch (_) {
      if (mounted && generation == _listenGen) {
        setState(() => _phase = VoicePhase.paused);
      }
      return;
    }
    if (generation != _listenGen) return;
    if (!keepWords || _turn.isEmpty) _armIdle();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(voiceIdlePause, () {
      if (!mounted || _phase != VoicePhase.listening || !_turn.isEmpty) return;
      _silence?.cancel();
      _ignoreEar = true;
      _ear.stop();
      _ignoreEar = false;
      setState(() => _phase = VoicePhase.paused);
    });
  }

  void _onWords(String words, bool isFinal) {
    if (!mounted || _phase != VoicePhase.listening || _muted) return;
    if (words.trim().isEmpty) return;
    _idle?.cancel();
    _emptyStops = 0;
    _turn.hear(words);
    setState(() => _userLine = _turn.text);
    _silence?.cancel();
    _silence = Timer(VoiceTurn.endpoint, () {
      final text = _turn.text.trim();
      if (text.isEmpty || _phase != VoicePhase.listening) return;
      _sendTurn(text);
    });
  }

  void _onLevel(double level) {
    if (!mounted || _phase != VoicePhase.listening) return;
    setState(() => _level = chatSoundLevel(level));
  }

  void _onStatus(String status) {
    if (!mounted || _muted || _ignoreEar || _starting) return;
    if (status != 'done' && status != 'notListening') return;
    if (_phase != VoicePhase.listening) return;
    _turn.engineStopped();
    if (_turn.isEmpty) {
      _emptyStops += 1;
      if (_emptyStops >= VoiceTurn.retryLimit) {
        _silence?.cancel();
        _idle?.cancel();
        setState(() => _phase = VoicePhase.paused);
        return;
      }
    } else {
      _emptyStops = 0;
      setState(() => _userLine = _turn.text);
    }
    _beginListen(keepWords: true);
  }

  void _onEarError() {
    if (!mounted || _muted || _ignoreEar || _starting) return;
    if (_phase != VoicePhase.listening) return;
    if (_turn.noteError()) {
      _beginListen(keepWords: true);
      return;
    }
    _silence?.cancel();
    _idle?.cancel();
    _listenGen++;
    setState(() => _phase = VoicePhase.paused);
    _ear.stop();
  }

  Future<void> _sendTurn(String text) async {
    if (_replyOpen || _phase == VoicePhase.thinking || _phase == VoicePhase.speaking) return;
    _silence?.cancel();
    _idle?.cancel();
    _turn.reset();
    _emptyStops = 0;
    _replyOpen = true;
    final generation = ++_playGen;
    _listenGen++;
    setState(() {
      _phase = VoicePhase.thinking;
      _userLine = text;
      _guideLine = '';
      _offline = false;
    });
    _ignoreEar = true;
    try {
      await _ear.stop();
    } catch (_) {}
    _ignoreEar = false;
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
    final speech = chat.replyLanguage(language);
    final t = AppLocalizations.of(context);
    if (widget.onSpeak == null) {
      final speaker = widget.speaker ?? DeviceChatSpeaker();
      _voice(speaker).beginReply();
    }
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
        _play(sentence, speech, generation);
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
        final chat = context.read<ChatController>();
        await chat.ensureNarratorVoice();
        if (!mounted || generation != _playGen) return;
        if (chat.elevenKey.trim().isNotEmpty && chat.elevenVoiceId.trim().isEmpty) {
          setState(() => _phoneVoice = true);
        }
        final speaker = widget.speaker ?? DeviceChatSpeaker();
        final narrator = _voice(speaker);
        narrator.onIdle = () {
          _pendingClips = 0;
          _afterSpeech(generation);
        };
        narrator.enqueue(
          sentence,
          languageCode: language,
          apiKey: () => chat.elevenKey,
          voiceId: () => chat.elevenVoiceId,
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
    return context.read<ChatController>().earLocale(language);
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
              if (_phoneVoice)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t.get('phoneVoiceNotice'),
                    key: const Key('voice-phone-notice'),
                    textAlign: TextAlign.center,
                    style: AppFonts.poppins(fontSize: 12, color: GuidePalette.muted),
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
                    return CustomPaint(
                      painter: MuseumOrbPainter(
                        phase: _phase,
                        pulse: _pulse.value,
                        level: _level,
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

/// Orbe de la pantalla Hablar. El azul vive solo aquí: la paleta del museo no tiene azul.
class MuseumOrbPainter extends CustomPainter {
  static const Color night = Color(0xFF14283F);
  static const Color blue = Color(0xFF3E6FA3);

  final VoicePhase phase;
  final double pulse;
  final double level;

  const MuseumOrbPainter({
    required this.phase,
    required this.pulse,
    required this.level,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final turn = pulse.clamp(0.0, 1.0);
    final volume = level.clamp(0.0, 1.0);
    final base = size.width * 0.26;

    canvas.drawCircle(
      center,
      size.width * 0.42,
      Paint()..color = night.withValues(alpha: 0.92),
    );

    if (phase == VoicePhase.thinking) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(turn * math.pi * 2);
      canvas.translate(-center.dx, -center.dy);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = GuidePalette.accent.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: base + 22),
        -0.4,
        2.1,
        false,
        glow,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: base + 34),
        2.2,
        1.3,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = blue.withValues(alpha: 0.9),
      );
      canvas.restore();
    }

    if (phase == VoicePhase.speaking) {
      for (var i = 0; i < 3; i++) {
        final wave = (turn * 2 + i / 3) % 1.0;
        canvas.drawCircle(
          center,
          base + 14 + wave * 48,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = (i.isEven ? GuidePalette.accent : GuidePalette.ink)
                .withValues(alpha: (1 - wave) * 0.62),
        );
      }
    }

    final listening = phase == VoicePhase.listening;
    final radius = base * (listening ? 1 + volume * 0.34 : 1 + math.sin(turn * math.pi * 2) * 0.03);
    final outline = Path();
    const steps = 56;
    for (var i = 0; i <= steps; i++) {
      final angle = (i / steps) * math.pi * 2;
      final wobble = listening ? 1 + volume * 0.09 * math.sin(angle * 5 + volume * 6) : 1.0;
      final point = Offset(
        center.dx + math.cos(angle) * radius * wobble,
        center.dy + math.sin(angle) * radius * wobble,
      );
      if (i == 0) {
        outline.moveTo(point.dx, point.dy);
      } else {
        outline.lineTo(point.dx, point.dy);
      }
    }
    outline.close();
    canvas.drawPath(
      outline,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFFF3E6C4),
            GuidePalette.accent,
            blue,
          ],
          stops: const [0.0, 0.46, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      Offset(center.dx - radius * 0.28, center.dy - radius * 0.32),
      radius * 0.16,
      Paint()..color = GuidePalette.ink.withValues(alpha: 0.38),
    );
  }

  @override
  bool shouldRepaint(covariant MuseumOrbPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.pulse != pulse || oldDelegate.level != level;
  }
}
