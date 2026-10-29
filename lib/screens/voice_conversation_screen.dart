import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_faq.dart';
import '../chat/remote_guide_answer_service.dart';
import '../chat/visit_context.dart';
import '../chat/xai_realtime.dart';
import '../core/locale/locale_controller.dart';
import '../core/theme/app_theme.dart';
import '../widgets/guide_orb.dart';
import 'app_localizations.dart';

Future<bool> voiceNetworkReachable() async {
  try {
    final result = await InternetAddress.lookup('api.x.ai').timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

enum VoicePhase { listening, thinking, speaking, paused }

enum VoiceSwitchChoice { keep, next, unclear }

/// Elige si el visitante quiere terminar el relato o escuchar la exhibición nueva.
VoiceSwitchChoice voiceSwitchChoice(String text) {
  final plain = text
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
  const keep = [
    'termin',
    'sigue',
    'seguir',
    'continu',
    'acab',
    'anterior',
    'primero',
    'contaba',
    'finish',
    'go on',
    'keep going',
    'weiter',
    'beende',
    'fertig',
    'zu ende',
  ];
  const next = [
    'nueva',
    'nuevo',
    'la otra',
    'el otro',
    'otra exhib',
    'cuentame',
    'cuenta esta',
    'the new',
    'new one',
    'neue',
    'anderen',
    'jetzt die',
  ];
  int first(List<String> words) {
    var best = 1 << 30;
    for (final word in words) {
      final at = plain.indexOf(word);
      if (at >= 0 && at < best) best = at;
    }
    return best;
  }

  final keepAt = first(keep);
  final nextAt = first(next);
  if (keepAt == 1 << 30 && nextAt == 1 << 30) return VoiceSwitchChoice.unclear;
  if (nextAt == 1 << 30) return VoiceSwitchChoice.keep;
  if (keepAt == 1 << 30) return VoiceSwitchChoice.next;
  return keepAt <= nextAt ? VoiceSwitchChoice.keep : VoiceSwitchChoice.next;
}

/// Conversación por voz a pantalla completa. El agente escucha y responde con voz.
class VoiceConversationScreen extends StatefulWidget {
  final XaiVoiceSession? session;
  final Future<bool> Function()? online;
  final Widget Function(BuildContext context, GuideOrbMood mood)? character;

  const VoiceConversationScreen({
    super.key,
    this.session,
    this.online,
    this.character,
  });

  @override
  State<VoiceConversationScreen> createState() => _VoiceConversationScreenState();
}

class _VoiceConversationScreenState extends State<VoiceConversationScreen>
    with WidgetsBindingObserver {
  XaiVoiceSession? _owned;
  XaiVoiceSession? _session;
  Timer? _errorFace;
  Timer? _think;
  VoicePhase _phase = VoicePhase.listening;
  GuideOrbMood _mood = GuideOrbMood.idle;
  bool _muted = false;
  bool _offline = false;
  bool _alive = false;
  bool _opening = false;
  bool _away = false;
  Future<void>? _leaving;
  bool _scripted = false;
  bool _stored = false;
  bool _switchAsk = false;
  bool _resolving = false;
  String? _boundPlaceId;
  String _heldSpeech = '';
  String _scriptUser = '';
  String _userLine = '';
  String _guideLine = '';
  VisitContext? _visit;
  int _generation = 0;

  XaiVoiceSession get _voice => _session ??= widget.session ?? (_owned = XaiRealtimeVoice());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_visit != null) return;
    final visit = context.read<ChatController>().visit;
    _visit = visit;
    _boundPlaceId = visit.place?.id;
    visit.addListener(_onExhibition);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visit?.removeListener(_onExhibition);
    _errorFace?.cancel();
    _think?.cancel();
    _generation++;
    final session = _session;
    _clearHooks(session);
    if (_owned != null) unawaited(_owned!.close());
    super.dispose();
  }

  void _clearHooks(XaiVoiceSession? session) {
    if (session == null) return;
    session.onVisitor = null;
    session.onVisitorText = null;
    session.onVisitorStopped = null;
    session.onGuideStart = null;
    session.onGuideText = null;
    session.onGuideDone = null;
    session.onFailure = null;
  }

  void _bind(XaiVoiceSession session) {
    session.onVisitor = _onVisitor;
    session.onVisitorText = _onVisitorText;
    session.onVisitorStopped = _onVisitorStopped;
    session.onGuideStart = _onGuideStart;
    session.onGuideText = _onGuideText;
    session.onGuideDone = _onGuideDone;
    session.onFailure = _onFailure;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_returnFromBackground());
      return;
    }
    unawaited(_leaveForeground());
  }

  /// Cierra el audio y el socket sin pintar el aviso de sin conexión.
  Future<void> _leaveForeground() {
    if (_away) return _leaving ?? Future.value();
    _away = true;
    _generation++;
    _alive = false;
    _opening = false;
    _think?.cancel();
    final session = _session;
    _leaving = () async {
      if (session == null) return;
      try {
        await session.close();
      } catch (_) {}
    }();
    return _leaving!;
  }

  /// Al volver, abre de nuevo la voz y recupera lo guardado del chat.
  Future<void> _returnFromBackground() async {
    if (!_away) return;
    final pending = _leaving;
    if (pending != null) await pending;
    _leaving = null;
    if (!mounted) return;
    _away = false;
    final chat = context.read<ChatController>();
    try {
      await chat.restoreSaved();
    } catch (_) {}
    if (!mounted || _away) return;
    if (_offline) {
      setState(() {
        _offline = false;
        _phase = VoicePhase.listening;
        _mood = GuideOrbMood.idle;
      });
    }
    _alive = false;
    _opening = false;
    await _open();
  }

  Future<bool> _reach() {
    if (widget.online != null) return widget.online!();
    if (const bool.fromEnvironment('FLUTTER_TEST') || Platform.environment['FLUTTER_TEST'] == 'true') {
      return Future.value(true);
    }
    return voiceNetworkReachable();
  }

  Future<void> _open() async {
    if (!mounted || _opening || _alive) return;
    _opening = true;
    final generation = ++_generation;
    final online = await _reach();
    if (!mounted || generation != _generation || _away) {
      _opening = false;
      return;
    }
    if (!online) {
      setState(() {
        _offline = true;
        _phase = VoicePhase.paused;
        _mood = GuideOrbMood.idle;
      });
      _opening = false;
      return;
    }
    final chat = context.read<ChatController>();
    final language = context.read<LocaleController>().locale.languageCode;
    if (chat.speechKey.isEmpty) {
      setState(() {
        _offline = false;
        _phase = VoicePhase.paused;
        _mood = GuideOrbMood.error;
        _guideLine = ChatFaq.missingKey(language);
      });
      _restAfterError();
      _opening = false;
      return;
    }
    final session = _voice;
    _bind(session);
    try {
      final instructions = await chat.voiceInstructions(language);
      if (!mounted || generation != _generation) return;
      final started = await session.start(
        apiKey: chat.speechKey,
        instructions: instructions,
        voice: chat.guideVoice,
        languageCode: chat.replyLanguage(language),
      );
      if (!mounted || generation != _generation || !started) return;
      _alive = true;
      session.setMuted(_muted);
      setState(() {
        _offline = false;
        _phase = VoicePhase.listening;
        _mood = GuideOrbMood.idle;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        _onFailure(XaiVoiceFailure.from(error, chat.speechKey));
      }
    } finally {
      _opening = false;
    }
  }

  void _onVisitor(bool speaking) {
    if (!mounted) return;
    if (speaking && !_scripted) {
      if (_phase == VoicePhase.speaking || _phase == VoicePhase.thinking) {
        unawaited(_voice.interrupt());
        if (!_switchAsk && !_stored) _remember();
      }
      if (_stored && !_switchAsk) {
        _userLine = '';
        _guideLine = '';
      }
    }
    setState(() {
      _mood = speaking ? GuideOrbMood.listen : _moodAfterVisitor();
      if (speaking && _phase != VoicePhase.paused) _phase = VoicePhase.listening;
    });
  }

  GuideOrbMood _moodAfterVisitor() {
    if (_phase == VoicePhase.speaking) return GuideOrbMood.speak;
    if (_phase == VoicePhase.thinking) return GuideOrbMood.idle;
    return GuideOrbMood.idle;
  }

  void _onVisitorStopped() {
    if (!mounted || _muted || _switchAsk || _scripted) return;
    _think?.cancel();
    _think = Timer(const Duration(seconds: 8), () {
      if (!mounted || _phase != VoicePhase.thinking) return;
      setState(() {
        _phase = VoicePhase.listening;
        _mood = GuideOrbMood.idle;
      });
    });
    setState(() {
      _phase = VoicePhase.thinking;
      _mood = GuideOrbMood.idle;
    });
  }

  void _onVisitorText(String text, {required bool replace, required bool ended}) {
    if (!mounted || _muted) return;
    final next = replace ? text : '$_userLine$text';
    setState(() => _userLine = next);
    _stored = false;
    if (ended && _switchAsk) unawaited(_answerSwitch(next));
  }

  void _onGuideStart() {
    if (!mounted) return;
    _think?.cancel();
    if (_scripted) {
      setState(() {
        _phase = VoicePhase.speaking;
        _mood = GuideOrbMood.speak;
      });
      return;
    }
    if (_switchAsk && _userLine.trim().isNotEmpty) {
      unawaited(_answerSwitch(_userLine));
      return;
    }
    setState(() {
      if (_stored) _guideLine = '';
      _stored = false;
      _phase = VoicePhase.speaking;
      _mood = GuideOrbMood.speak;
    });
  }

  void _onGuideText(String text, {required bool replace}) {
    if (!mounted || _scripted) return;
    _think?.cancel();
    setState(() {
      _phase = VoicePhase.speaking;
      _mood = GuideOrbMood.speak;
      _guideLine = replace ? text : '$_guideLine$text';
    });
  }

  void _onGuideDone() {
    if (!mounted) return;
    _think?.cancel();
    final chat = context.read<ChatController>();
    if (_scripted) {
      final line = _guideLine.trim();
      final asked = _scriptUser.trim();
      _scripted = false;
      _scriptUser = '';
      if (asked.isNotEmpty) {
        chat.rememberExchange(asked, line);
        _stored = true;
      } else if (_switchAsk && line.isNotEmpty) {
        chat.rememberExchange('', line);
        _stored = true;
      }
    } else {
      _remember();
    }
    if (_phase == VoicePhase.paused || _offline) return;
    setState(() {
      _phase = VoicePhase.listening;
      _mood = GuideOrbMood.idle;
    });
  }

  void _onFailure(XaiVoiceFailure failure) {
    if (!mounted || _away) return;
    _think?.cancel();
    _alive = false;
    _scripted = false;
    _switchAsk = false;
    _resolving = false;
    if (failure.offline) {
      setState(() {
        _offline = true;
        _phase = VoicePhase.paused;
        _mood = GuideOrbMood.idle;
      });
      return;
    }
    final chat = context.read<ChatController>();
    final language = context.read<LocaleController>().locale.languageCode;
    final shown = failure.microphone
        ? AppLocalizations.of(context).get('voiceMicDenied')
        : RemoteGuideAnswerService.visibleError(
            failure.status,
            DeepSeekLog.safe(failure.detail, chat.speechKey),
          );
    if (_userLine.trim().isNotEmpty && shown.isNotEmpty) {
      chat.rememberExchange(_userLine, shown);
      _stored = true;
    }
    setState(() {
      _offline = false;
      _phase = VoicePhase.paused;
      _mood = GuideOrbMood.error;
      if (shown.isNotEmpty) _guideLine = shown;
    });
    _restAfterError();
  }

  void _restAfterError() {
    _errorFace?.cancel();
    _errorFace = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _mood != GuideOrbMood.error) return;
      setState(() => _mood = GuideOrbMood.idle);
    });
  }

  void _remember() {
    if (_stored || !mounted) return;
    final asked = _userLine.trim();
    final reply = _guideLine.trim();
    if (asked.isEmpty && reply.isEmpty) return;
    context.read<ChatController>().rememberExchange(asked, reply);
    _stored = true;
  }

  void _onExhibition() {
    if (!mounted) return;
    final next = _visit?.place?.id;
    if (next == _boundPlaceId || _switchAsk) return;
    final speaking = _phase == VoicePhase.speaking || _phase == VoicePhase.thinking;
    if (!speaking) {
      _boundPlaceId = next;
      unawaited(_rebind());
      return;
    }
    _switchAsk = true;
    _heldSpeech = _guideLine.trim();
    _remember();
    _userLine = '';
    _stored = true;
    unawaited(_speakScript(AppLocalizations.of(context).get('voiceSwitchAsk')));
  }

  Future<void> _rebind() async {
    if (!mounted || !_alive) return;
    final chat = context.read<ChatController>();
    final language = context.read<LocaleController>().locale.languageCode;
    final instructions = await chat.voiceInstructions(language);
    if (!mounted || !_alive) return;
    await _voice.update(
      instructions: instructions,
      voice: chat.guideVoice,
      languageCode: chat.replyLanguage(language),
    );
  }

  Future<void> _speakScript(String line, {String asUser = ''}) async {
    final spoken = line.trim();
    if (spoken.isEmpty || !mounted) return;
    _scripted = true;
    _scriptUser = asUser;
    _stored = false;
    setState(() {
      _phase = VoicePhase.speaking;
      _mood = GuideOrbMood.speak;
      _guideLine = spoken;
    });
    await _voice.interrupt();
    if (!mounted) return;
    await _voice.say(spoken);
  }

  Future<void> _answerSwitch(String text) async {
    if (!mounted || !_switchAsk || _resolving) return;
    _resolving = true;
    final choice = voiceSwitchChoice(text);
    final t = AppLocalizations.of(context);
    final chat = context.read<ChatController>();
    if (choice == VoiceSwitchChoice.unclear) {
      _resolving = false;
      await _speakScript(t.get('voiceSwitchAsk'));
      return;
    }
    _switchAsk = false;
    _resolving = false;
    _boundPlaceId = _visit?.place?.id;
    if (choice == VoiceSwitchChoice.keep) {
      final held = _heldSpeech.trim();
      await _speakScript(
        held.isEmpty ? t.get('voiceSwitchEmpty') : held,
        asUser: text,
      );
      return;
    }
    await _rebind();
    if (!mounted) return;
    final question = t.get('voiceSwitchNew');
    _scripted = false;
    _stored = false;
    setState(() {
      _userLine = question;
      _guideLine = '';
      _phase = VoicePhase.thinking;
      _mood = GuideOrbMood.idle;
    });
    await _voice.interrupt();
    if (!mounted) return;
    await _voice.ask(question);
  }

  Future<void> _interrupt() async {
    _generation++;
    _think?.cancel();
    final pending = _switchAsk;
    _switchAsk = false;
    _scripted = false;
    _resolving = false;
    _remember();
    await _voice.interrupt();
    if (pending) {
      _boundPlaceId = _visit?.place?.id;
      await _rebind();
    }
    if (!mounted) return;
    setState(() {
      _phase = VoicePhase.listening;
      _mood = GuideOrbMood.idle;
    });
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    _voice.setMuted(_muted);
    if (mounted) setState(() {});
  }

  Future<void> _exit() async {
    _generation++;
    _think?.cancel();
    _errorFace?.cancel();
    _remember();
    await _voice.interrupt();
    if (_owned != null) await _owned!.close();
    _alive = false;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _resumeFromPause() async {
    _muted = false;
    _offline = false;
    if (!_alive) {
      await _open();
      return;
    }
    _voice.setMuted(false);
    if (!mounted) return;
    setState(() {
      _phase = VoicePhase.listening;
      _mood = GuideOrbMood.idle;
    });
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
    final character = widget.character?.call(context, _mood) ?? GuideOrb(mood: _mood);

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
              Flexible(
                child: GestureDetector(
                  key: const Key('voice-sphere'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_phase == VoicePhase.paused) {
                      _resumeFromPause();
                      return;
                    }
                    if (_phase == VoicePhase.speaking || _phase == VoicePhase.thinking) {
                      _interrupt();
                    }
                  },
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final height = constraints.maxHeight;
                        final bound = width < height ? width : height;
                        final side = !bound.isFinite
                            ? GuideOrb.diameter
                            : (bound > GuideOrb.diameter ? GuideOrb.diameter : bound);
                        return SizedBox(width: side, height: side, child: character);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
