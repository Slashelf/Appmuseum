import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_message.dart';
import '../chat/chat_voice.dart';
import '../chat/guide_narrator.dart';
import '../chat/local_exhibition_answers.dart';
import '../core/locale/locale_controller.dart';
import '../core/navigation/place_navigation.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';
import 'beacon_scan_services.dart';
import 'guide_settings_screen.dart';
import 'voice_conversation_screen.dart';

class ChatScreen extends StatefulWidget {
  final ChatEar? ear;
  final ChatSpeaker? speaker;

  const ChatScreen({super.key, this.ear, this.speaker});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const micExplainedKey = 'chat_mic_explained';
  static const autoSendKey = 'chat_mic_auto_send';
  static const conversationKey = 'chat_voice_conversation';
  static const _slideDistance = 80.0;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ChatEar? _ownedEar;
  ChatSpeaker? _ownedSpeaker;
  GuideNarrator? _narrator;
  bool _sending = false;
  bool _listening = false;
  bool _autoSend = false;
  bool _conversation = false;
  bool _micExplained = false;
  bool _ignoreFinish = false;
  bool _thenListen = false;
  bool _followBottom = true;
  bool _dragging = false;
  bool _localQuestionsOpen = true;
  bool _phoneVoice = false;
  bool _fingerDown = false;
  bool _holding = false;
  bool _locked = false;
  bool _holdClosing = false;
  bool _sawDraft = false;
  int _holdGen = 0;
  int _holdSeconds = 0;
  Offset? _origin;
  Offset _drag = Offset.zero;
  Timer? _clock;
  double? _lastInset;
  double _level = 0;
  String _textBeforeMic = '';
  String _heard = '';
  int? _speakingIndex;
  final GlobalKey _latestReplyKey = GlobalKey();

  ChatEar get _ear => widget.ear ?? (_ownedEar ??= DeviceChatEar());

  ChatSpeaker get _speaker => widget.speaker ?? (_ownedSpeaker ??= DeviceChatSpeaker());

  @override
  void initState() {
    super.initState();
    _input.addListener(_onDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareChat();
      _scrollToBottomNow();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final previous = _lastInset;
    _lastInset = inset;
    if (previous == null || inset <= previous) return;
    final growth = inset - previous;
    // The keyboard covers the composer. Stay at the latest line, or keep the
    // line the visitor was already reading above the composer.
    final stayAtEnd = _followBottom || _nearBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (stayAtEnd) {
        position.jumpTo(position.maxScrollExtent);
        return;
      }
      final next = (position.pixels + growth).clamp(0.0, position.maxScrollExtent);
      if ((next - position.pixels).abs() < 0.5) return;
      position.jumpTo(next);
    });
  }

  Future<void> _prepareChat() async {
    if (!mounted) return;
    final chat = context.read<ChatController>();
    try {
      await chat.restoreSaved();
      final prefs = await SharedPreferences.getInstance();
      _autoSend = prefs.getBool(autoSendKey) ?? false;
      _conversation = prefs.getBool(conversationKey) ?? false;
      _micExplained = prefs.getBool(micExplainedKey) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    _scrollToBottomNow();
    final t = AppLocalizations.of(context);
    try {
      await BeaconServiceFlutter().ensureScan(
        permissionDeniedMessage: t.get('blePermissionDenied'),
        onMessage: (message) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _ignoreFinish = true;
    final wasListening = _listening;
    _listening = false;
    if (wasListening) {
      _ear.cancel();
    }
    _clock?.cancel();
    _input.removeListener(_onDraft);
    _ownedSpeaker?.stop();
    final narrator = _narrator;
    _narrator = null;
    if (narrator != null) unawaited(narrator.dispose());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    final chat = context.read<ChatController>();
    final language = context.read<LocaleController>().locale.languageCode;
    final t = AppLocalizations.of(context);
    final noData = t.get('chatNoData');
    final aiUnavailable = t.get('aiUnavailable');
    if (_listening) {
      _ignoreFinish = true;
      _listening = false;
      _holding = false;
      _locked = false;
      _level = 0;
      _stopClock();
      await _ear.stop();
    }
    if (!mounted) return;
    setState(() => _sending = true);
    _input.clear();
    _heard = '';
    // A new line follows the bottom only when the visitor was already there.
    if (_followBottom) _revealBottom();
    if (_conversation) _guideNarrator().beginReply();
    await chat.submit(
      text,
      languageCode: language,
      noDataText: noData,
      aiUnavailableText: aiUnavailable,
      spoken: _conversation,
      onSentence: _conversation
          ? (sentence) {
              unawaited(_speakRemote(sentence));
            }
          : null,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (_followBottom) _placeReply();
    final narratorBusy = _narrator?.busy ?? false;
    if (_conversation &&
        !narratorBusy &&
        chat.messages.isNotEmpty &&
        chat.messages.last.role == ChatRole.guide) {
      await _toggleSpeak(
        chat.messages.length - 1,
        chat.messages.last.text,
        thenListen: true,
      );
    }
  }

  GuideNarrator _guideNarrator() {
    final narrator = _narrator ??= GuideNarrator(fallback: _speaker);
    narrator.onIdle = () {
      if (!mounted || !_conversation || _sending || _listening) return;
      _startListen();
    };
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

  Future<void> _speakRemote(String sentence) async {
    final chat = context.read<ChatController>();
    await chat.ensureNarratorVoice();
    if (!mounted) return;
    final ui = context.read<LocaleController>().locale.languageCode;
    _guideNarrator().enqueue(
      sentence,
      languageCode: chat.replyLanguage(ui),
      apiKey: () => chat.speechKey,
      voiceId: () => chat.guideVoice,
    );
  }

  String _localeId(String language) {
    return context.read<ChatController>().earLocale(language);
  }

  String get _clockLabel {
    final minutes = _holdSeconds ~/ 60;
    final seconds = (_holdSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onDraft() {
    if (!mounted || _listening || _holding) return;
    final has = _input.text.trim().isNotEmpty;
    if (has == _sawDraft) return;
    _sawDraft = has;
    setState(() {});
  }

  void _buzz() {
    unawaited(() async {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
    }());
  }

  void _restoreMicText() {
    _input.text = _textBeforeMic;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  void _notice(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 108),
        content: Text(AppLocalizations.of(context).get(key)),
      ),
    );
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<bool> _explainMic() async {
    final t = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.get('micExplainTitle'), style: AppFonts.poppins(fontWeight: FontWeight.w600)),
          content: Text(t.get('micExplainBody'), style: AppFonts.poppins(fontSize: 15, height: 1.35)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.get('micExplainLater')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.get('micExplainContinue')),
            ),
          ],
        );
      },
    );
    return answer == true;
  }

  Future<void> _startListen({bool hold = false}) async {
    if (_sending || _listening || _speakingIndex != null) return;
    final gen = _holdGen;
    if (!_micExplained) {
      final agreed = await _explainMic();
      if (!agreed || !mounted) return;
      _micExplained = true;
      await _saveBool(micExplainedKey, true);
    }
    if (!mounted || (hold && gen != _holdGen)) return;
    _textBeforeMic = _input.text;
    _heard = '';
    _ignoreFinish = false;
    final language = context.read<LocaleController>().locale.languageCode;
    final localeId = _localeId(language);
    final ready = await _ear.prepare(
      onStatus: _onListenStatus,
      onError: _onEarError,
    );
    if (!ready) {
      _notice('micUnavailable');
      return;
    }
    if (!mounted || (hold && gen != _holdGen)) return;
    setState(() {
      _listening = true;
      _level = 0;
    });
    try {
      await _ear.listen(
        onWords: _onWords,
        onLevel: _onLevel,
        localeId: localeId,
        options: hold ? chatHoldListenOptions(localeId) : chatListenOptions(localeId),
      );
    } catch (_) {
      _listening = false;
      _restoreMicText();
      if (mounted) setState(() {});
      _notice('micUnavailable');
    }
    if (hold && gen != _holdGen && _listening) {
      await _cancelListen();
    }
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
    _holdSeconds = 0;
  }

  void _startClock() {
    _stopClock();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || (!_holding && !_locked)) return;
      setState(() => _holdSeconds += 1);
    });
  }

  Future<void> _cancelListen() async {
    _ignoreFinish = true;
    _listening = false;
    _holding = false;
    _locked = false;
    _fingerDown = false;
    _level = 0;
    _heard = '';
    _drag = Offset.zero;
    _stopClock();
    _restoreMicText();
    if (mounted) setState(() {});
    try {
      await _ear.cancel();
    } catch (_) {}
  }

  void _micDown(PointerDownEvent event) {
    if (_sending || _speakingIndex != null || _listening || _holding) return;
    _fingerDown = true;
    _origin = event.position;
    _drag = Offset.zero;
    unawaited(_openHold());
  }

  Future<void> _openHold() async {
    if (!_micExplained) {
      _fingerDown = false;
      final agreed = await _explainMic();
      if (!agreed || !mounted) return;
      _micExplained = true;
      await _saveBool(micExplainedKey, true);
      return;
    }
    await _armHold();
  }

  Future<void> _armHold() async {
    _holdGen += 1;
    final gen = _holdGen;
    _holding = true;
    _locked = false;
    _holdSeconds = 0;
    _drag = Offset.zero;
    if (mounted) setState(() {});
    await _startListen(hold: true);
    if (!mounted || gen != _holdGen) return;
    if (!_listening) {
      _holding = false;
      if (mounted) setState(() {});
      return;
    }
    _startClock();
    _buzz();
    if (!mounted || gen != _holdGen) return;
    if (!_fingerDown && !_locked) {
      await _endHold(cancel: _drag.dx <= -_slideDistance);
      return;
    }
    if (mounted) setState(() {});
  }

  void _micMove(PointerMoveEvent event) {
    if (!_fingerDown || _origin == null) return;
    final delta = event.position - _origin!;
    _drag = delta;
    if (!_locked && delta.dy <= -_slideDistance && delta.dy.abs() > delta.dx.abs()) {
      _locked = true;
      if (mounted) setState(() {});
      return;
    }
    if (mounted) setState(() {});
  }

  void _micUp(PointerEvent event) {
    final wasDown = _fingerDown;
    _fingerDown = false;
    if (_locked) {
      _holding = false;
      if (mounted) setState(() {});
      return;
    }
    if (!wasDown || (!_holding && !_listening)) return;
    unawaited(_endHold(cancel: _drag.dx <= -_slideDistance));
  }

  Future<void> _endHold({required bool cancel}) async {
    if (_holdClosing) return;
    _holdClosing = true;
    _holdGen += 1;
    _holding = false;
    _locked = false;
    _fingerDown = false;
    _drag = Offset.zero;
    _stopClock();
    final text = _heard.trim();
    final wasListening = _listening;
    if (wasListening) {
      _ignoreFinish = true;
      _listening = false;
      _level = 0;
    }
    if (mounted) setState(() {});
    try {
      if (cancel) {
        if (wasListening) await _cancelListen();
        return;
      }
      if (!wasListening) return;
      try {
        await _ear.stop();
      } catch (_) {}
      if (!mounted) return;
      if (text.isEmpty) {
        _restoreMicText();
        setState(() {});
        _notice('micNotHeard');
        return;
      }
      _buzz();
      _input.text = text;
      await _send(text);
    } finally {
      _holdClosing = false;
      if (mounted) setState(() {});
    }
  }

  void _onWords(String words, bool isFinal) {
    if (!mounted || !_listening) return;
    if (words.trim().isEmpty) return;
    _heard = words;
    setState(() {
      _input.text = words;
      _input.selection = TextSelection.collapsed(offset: words.length);
    });
  }

  void _onLevel(double level) {
    if (!mounted || !_listening) return;
    setState(() => _level = chatSoundLevel(level));
  }

  void _onListenStatus(String status) {
    if (!mounted) return;
    if (status != 'done' && status != 'notListening') return;
    if (!_listening) return;
    _onFinished();
  }

  void _onEarError() {
    if (!_listening) return;
    _ignoreFinish = true;
    _listening = false;
    _holding = false;
    _locked = false;
    _level = 0;
    _stopClock();
    _restoreMicText();
    if (mounted) setState(() {});
    _notice('micUnavailable');
  }

  void _onFinished() {
    if (_ignoreFinish) {
      _ignoreFinish = false;
      return;
    }
    if (!_listening) return;
    if (_holding || _locked) {
      unawaited(_endHold(cancel: false));
      return;
    }
    final text = _heard.trim();
    setState(() {
      _listening = false;
      _level = 0;
    });
    if (text.isEmpty) {
      _restoreMicText();
      _notice('micNotHeard');
      return;
    }
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    if (_autoSend) {
      _send(text);
    }
  }

  Future<void> _toggleSpeak(int index, String text, {bool thenListen = false}) async {
    final spoken = text.trim();
    if (spoken.isEmpty || _sending) return;
    if (_speakingIndex == index) {
      _thenListen = false;
      await _speaker.stop();
      if (mounted) setState(() => _speakingIndex = null);
      return;
    }
    if (_listening) {
      _ignoreFinish = true;
      _listening = false;
      _holding = false;
      _locked = false;
      _level = 0;
      _stopClock();
      await _ear.stop();
    }
    _thenListen = thenListen || _conversation;
    if (!mounted) return;
    setState(() => _speakingIndex = index);
    final ui = context.read<LocaleController>().locale.languageCode;
    final language = context.read<ChatController>().replyLanguage(ui);
    try {
      await _speaker.speak(
        text: spoken,
        languageCode: language,
        onDone: () {
          if (!mounted) return;
          final resume = _thenListen && _conversation && _speakingIndex == index;
          _thenListen = false;
          setState(() {
            if (_speakingIndex == index) _speakingIndex = null;
          });
          if (resume) _startListen();
        },
      );
    } catch (_) {
      _thenListen = false;
      if (mounted) setState(() => _speakingIndex = null);
    }
  }

  bool _nearBottom() {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    return position.maxScrollExtent - position.pixels <= 48;
  }

  void _setFollow(bool value) {
    if (!mounted || _followBottom == value) return;
    setState(() => _followBottom = value);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification) {
      _dragging = notification.dragDetails != null;
      return false;
    }
    if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      _dragging = true;
      _setFollow(_nearBottom());
      return false;
    }
    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _setFollow(_nearBottom());
    }
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    _keepFollowing();
    return false;
  }

  void _keepFollowing() {
    if (!_followBottom || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels <= 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followBottom || !_scroll.hasClients) return;
      final latest = _scroll.position.maxScrollExtent;
      if ((latest - _scroll.position.pixels).abs() <= 1) return;
      _scroll.jumpTo(latest);
    });
  }

  void _scrollToBottomNow() {
    if (!mounted || !_followBottom || !_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if ((_scroll.position.pixels - target).abs() < 1) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _revealBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottomNow());
  }

  void _jumpToLatest() {
    _setFollow(true);
    _revealBottom();
  }

  void _placeReply() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followBottom || !_scroll.hasClients) return;
      final target = _latestReplyKey.currentContext;
      if (target == null) {
        _scrollToBottomNow();
        return;
      }
      final bubble = target.size?.height ?? 0;
      if (bubble > _scroll.position.viewportDimension) {
        _setFollow(false);
        Scrollable.ensureVisible(
          target,
          alignment: 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
        return;
      }
      Scrollable.ensureVisible(
        target,
        alignment: 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final language = context.watch<LocaleController>().locale.languageCode;
    final chat = context.watch<ChatController>();
    final place = chat.visit.place?.localized(language);
    final placeName = (place?.name.trim().isNotEmpty ?? false)
        ? place!.name
        : place?.name2;
    final messages = chat.messages;
    final latestGuide = messages.lastIndexWhere((message) => message.role == ChatRole.guide);

    return Scaffold(
      backgroundColor: GuidePalette.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: GuidePalette.white,
        title: Text(
          t.get('chatTitle'),
          style: AppFonts.poppins(
            color: GuidePalette.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            key: const Key('chat-menu'),
            tooltip: t.get('settingsTitle'),
            color: GuidePalette.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GuidePalette.radiusCard),
              side: const BorderSide(color: GuidePalette.accent),
            ),
            icon: const Icon(Icons.more_vert, color: GuidePalette.white),
            onSelected: (value) => _onMenu(value, chat),
            itemBuilder: (context) => _menuItems(t, chat),
          ),
        ],
      ),
      body: Column(
        children: [
          if (placeName != null && placeName.trim().isNotEmpty)
            _exhibitionBar(t, chat, placeName),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: _onMetrics,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: ListView(
                        key: const Key('chat-thread'),
                        controller: _scroll,
                        // Keep the whole visit built so a new question can scroll into view.
                        cacheExtent: 20000,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        children: [
                          if (messages.isEmpty)
                            _Bubble(
                              mine: false,
                              text: t.get('chatWelcome'),
                              speakKey: const Key('chat-speak-welcome'),
                              speaking: _speakingIndex == -1,
                              speakTip: _speakingIndex == -1 ? t.get('micStopSpeak') : t.get('micSpeak'),
                              onSpeak: () => _toggleSpeak(-1, t.get('chatWelcome')),
                            ),
                          for (var i = 0; i < messages.length; i++)
                            _Bubble(
                              key: i == latestGuide ? _latestReplyKey : null,
                              mine: messages[i].role == ChatRole.visitor,
                              text: messages[i].text,
                              speakKey: Key('chat-speak-$i'),
                              speaking: _speakingIndex == i,
                              speakTip: _speakingIndex == i ? t.get('micStopSpeak') : t.get('micSpeak'),
                              onSpeak: messages[i].role == ChatRole.guide
                                  ? () => _toggleSpeak(i, messages[i].text)
                                  : null,
                            ),
                          if (_sending)
                            Padding(
                              key: const Key('chat-typing'),
                              padding: const EdgeInsets.only(left: 4, bottom: 10),
                              child: Text(
                                t.get('chatTyping'),
                                style: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_followBottom)
                  Positioned(
                    right: 12,
                    bottom: 8,
                    child: Tooltip(
                      message: t.get('chatJump'),
                      child: Material(
                        color: GuidePalette.accent,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: const Key('chat-jump'),
                          customBorder: const CircleBorder(),
                          onTap: _jumpToLatest,
                          child: const SizedBox(
                            width: 42,
                            height: 42,
                            child: Center(
                              child: Text(
                                '↓',
                                style: TextStyle(
                                  color: GuidePalette.onAccent,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (chat.mode == ChatAnswerMode.local)
            _localQuestions(t, chat, language)
          else
            SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _holding || _locked
                        ? _holdBar(t)
                        : TextField(
                            controller: _input,
                            style: AppFonts.poppins(fontSize: 15),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: t.get('chatHint'),
                              hintStyle: AppFonts.poppins(
                                fontSize: 15,
                                color: GuidePalette.muted,
                              ),
                              filled: true,
                              fillColor: GuidePalette.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(color: GuidePalette.accent),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(
                                  color: GuidePalette.accent,
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                  ),
                  if (_listening && !_holding && !_locked) ...[
                    const SizedBox(width: 6),
                    _MicBars(level: _level),
                    IconButton(
                      key: const Key('chat-mic-cancel'),
                      tooltip: t.get('micCancel'),
                      onPressed: _cancelListen,
                      icon: const Icon(Icons.close, color: GuidePalette.muted),
                    ),
                  ],
                  if (_sending)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: GuidePalette.accent,
                        ),
                      ),
                    )
                  else if (_locked)
                    IconButton(
                      key: const Key('chat-mic-send'),
                      tooltip: t.get('chatSend'),
                      onPressed: () => _endHold(cancel: false),
                      icon: const Icon(Icons.send, color: GuidePalette.accent),
                    )
                  else if (_input.text.trim().isNotEmpty && !_listening && !_holding)
                    IconButton(
                      key: const Key('chat-send'),
                      tooltip: t.get('chatSend'),
                      onPressed: () => _send(),
                      icon: const Icon(Icons.send, color: GuidePalette.accent),
                    )
                  else
                    Listener(
                      key: const Key('chat-mic'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _micDown,
                      onPointerMove: _micMove,
                      onPointerUp: _micUp,
                      onPointerCancel: _micUp,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          color: _listening ? GuidePalette.accent : GuidePalette.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _holdBar(AppLocalizations t) {
    final armed = !_locked && _drag.dx <= -_slideDistance;
    return Row(
      children: [
        Text(
          _clockLabel,
          key: const Key('chat-mic-clock'),
          style: AppFonts.poppins(fontSize: 14, color: GuidePalette.ink),
        ),
        const SizedBox(width: 8),
        _MicBars(level: _level),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _locked ? t.get('micLocked') : t.get('micSlideCancel'),
            key: const Key('chat-mic-slide'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.poppins(
              fontSize: 14,
              color: armed ? GuidePalette.accent : GuidePalette.muted,
            ),
          ),
        ),
        if (_locked)
          const Icon(Icons.lock, key: Key('chat-mic-lock'), color: GuidePalette.accent, size: 20),
        IconButton(
          key: const Key('chat-mic-cancel'),
          tooltip: t.get('micCancel'),
          onPressed: _cancelListen,
          icon: const Icon(Icons.close, color: GuidePalette.muted),
        ),
      ],
    );
  }

  Widget _exhibitionBar(AppLocalizations t, ChatController chat, String placeName) {
    final cloudVoice = chat.speechKey.isNotEmpty;
    return Container(
      width: double.infinity,
      color: GuidePalette.background,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.get('chatHere').replaceAll('{name}', placeName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: GuidePalette.accent,
                  ),
                ),
              ),
              if (_conversation)
                Tooltip(
                  message: cloudVoice ? 'Grok' : t.get('audioVoice'),
                  child: Container(
                    key: const Key('chat-voice-dot'),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: cloudVoice ? GuidePalette.accent : GuidePalette.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          if (_phoneVoice)
            Text(
              t.get('phoneVoiceNotice'),
              key: const Key('chat-phone-voice'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.poppins(fontSize: 11, color: GuidePalette.muted),
            ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(AppLocalizations t, ChatController chat) {
    final local = chat.mode == ChatAnswerMode.local;
    final items = <PopupMenuEntry<String>>[
      GuideMenuItem(
        key: const Key('chat-mode-local'),
        value: 'local',
        checked: local,
        icon: Icons.place_outlined,
        label: t.get('modeLocalLabel'),
      ),
      GuideMenuItem(
        key: const Key('chat-mode-chatbot'),
        value: 'chatbot',
        checked: !local,
        icon: Icons.chat_bubble_outline,
        label: t.get('modeChatbotLabel'),
      ),
    ];
    if (!local) {
      items.addAll([
        GuideMenuItem(
          key: const Key('chat-voice'),
          value: 'voice',
          checked: _conversation,
          icon: Icons.graphic_eq,
          label: t.get('voiceToggle'),
        ),
        GuideMenuItem(
          key: const Key('chat-auto-send'),
          value: 'auto',
          checked: _autoSend,
          icon: Icons.send_outlined,
          label: t.get('micAutoSend'),
        ),
        GuideMenuItem(
          key: const Key('chat-mic-language'),
          value: 'mic',
          icon: Icons.language,
          label: t.get('micLanguage'),
        ),
        GuideMenuItem(
          key: const Key('chat-talk'),
          value: 'talk',
          icon: Icons.mic_none,
          label: t.get('voiceTalk'),
        ),
        GuideMenuItem(
          key: const Key('chat-stop-audio'),
          value: 'stop',
          icon: Icons.stop_circle_outlined,
          label: t.get('voiceStop'),
        ),
      ]);
    }
    items.addAll([
      GuideMenuItem(
        key: const Key('chat-settings'),
        value: 'settings',
        icon: Icons.settings_outlined,
        label: t.get('settingsTitle'),
      ),
      GuideMenuItem(
        key: const Key('chat-clear'),
        value: 'clear',
        icon: Icons.delete_outline,
        label: t.get('clearChat'),
      ),
    ]);
    return items;
  }

  Future<void> _onMenu(String value, ChatController chat) async {
    switch (value) {
      case 'local':
        await chat.setMode(ChatAnswerMode.local);
        BeaconServiceFlutter().recoverScan();
      case 'chatbot':
        await chat.setMode(ChatAnswerMode.deepseek);
        BeaconServiceFlutter().recoverScan();
      case 'voice':
        final next = !_conversation;
        setState(() => _conversation = next);
        await _saveBool(conversationKey, next);
        if (!next) await _stopAudio();
      case 'auto':
        final next = !_autoSend;
        setState(() => _autoSend = next);
        await _saveBool(autoSendKey, next);
      case 'mic':
        await _pickMicLanguage(chat);
      case 'talk':
        await _openVoice(chat);
      case 'stop':
        await _stopAudio();
      case 'settings':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const GuideSettingsScreen()),
        );
      case 'clear':
        await _confirmClear(chat);
    }
  }

  Future<void> _pickMicLanguage(ChatController chat) async {
    final t = AppLocalizations.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
        Widget option(String code, String labelKey, Key key) {
          final selected = chat.micLanguage == code;
          return SimpleDialogOption(
            key: key,
            onPressed: () => Navigator.pop(context, code),
            child: Text(
              selected ? '${t.get(labelKey)} ✓' : t.get(labelKey),
              style: AppFonts.poppins(fontSize: 15),
            ),
          );
        }

        return SimpleDialog(
          title: Text(
            t.get('micLanguage'),
            style: AppFonts.poppins(fontWeight: FontWeight.w600),
          ),
          children: [
            option('auto', 'micLangAuto', const Key('chat-mic-auto')),
            option('es', 'micLangSpanish', const Key('chat-mic-es')),
            option('en', 'micLangEnglish', const Key('chat-mic-en')),
            option('pt', 'micLangPortuguese', const Key('chat-mic-pt')),
          ],
        );
      },
    );
    if (choice == null) return;
    await chat.setMicLanguage(choice);
  }

  Future<void> _confirmClear(ChatController chat) async {
    final t = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t.get('clearChat'), style: AppFonts.poppins(fontWeight: FontWeight.w600)),
          content: Text(
            t.get('clearChatBody'),
            style: AppFonts.poppins(fontSize: 15, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.get('clearChatNo')),
            ),
            TextButton(
              key: const Key('chat-clear-yes'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.get('clearChatYes')),
            ),
          ],
        );
      },
    );
    if (answer == true) chat.clearConversation();
  }

  Widget _localQuestions(AppLocalizations t, ChatController chat, String language) {
    Widget button(String label, LocalExhibitionQuestion question, Key key) {
      return OutlinedButton(
        key: key,
        onPressed: () => chat.askStored(
          question,
          languageCode: language,
          label: label,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: GuidePalette.ink,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: const BorderSide(color: GuidePalette.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(
          label,
          style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (!_localQuestionsOpen) {
      return SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('chat-local-show'),
            onPressed: () => setState(() => _localQuestionsOpen = true),
            child: Text(t.get('localQuestionsShow')),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: ListView(
                key: const Key('chat-local-row'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  button(
                    t.get('localAskFounded'),
                    LocalExhibitionQuestion.founded,
                    const Key('chat-local-founded'),
                  ),
                  const SizedBox(width: 8),
                  button(
                    t.get('localAskImages'),
                    LocalExhibitionQuestion.images,
                    const Key('chat-local-images'),
                  ),
                  const SizedBox(width: 8),
                  button(
                    t.get('localAskVisit'),
                    LocalExhibitionQuestion.visit,
                    const Key('chat-local-visit'),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('chat-local-hide'),
              tooltip: t.get('localQuestionsHide'),
              onPressed: () => setState(() => _localQuestionsOpen = false),
              icon: const Icon(Icons.expand_more, color: GuidePalette.muted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopAudio() async {
    _thenListen = false;
    await _narrator?.stop();
    await _speaker.stop();
    if (mounted) setState(() => _speakingIndex = null);
  }

  Future<void> _openVoice(ChatController chat) async {
    if (_listening) await _cancelListen();
    await _stopAudio();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: GuideRoutes.talk),
        builder: (_) => VoiceConversationScreen(
          ear: widget.ear,
          speaker: widget.speaker,
        ),
      ),
    );
  }
}

class _MicBars extends StatefulWidget {
  final double level;

  const _MicBars({required this.level});

  @override
  State<_MicBars> createState() => _MicBarsState();
}

class _MicBarsState extends State<_MicBars> with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const shape = [0.45, 0.7, 1.0, 0.75, 0.5];
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, _) {
        return Row(
          key: const Key('chat-mic-level'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < shape.length; i++)
              Container(
                width: 3,
                height: 6 + (4 + 16 * widget.level) * shape[i] * (0.45 + 0.55 * ((i.isEven ? _wave.value : 1 - _wave.value))),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: GuidePalette.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool mine;
  final String text;
  final VoidCallback? onSpeak;
  final bool speaking;
  final String speakTip;
  final Key? speakKey;

  const _Bubble({
    super.key,
    required this.mine,
    required this.text,
    this.onSpeak,
    this.speaking = false,
    this.speakTip = '',
    this.speakKey,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? GuidePalette.accent : GuidePalette.card,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: const Color(0x11000000)),
          boxShadow: mine
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: AppFonts.poppins(
                fontSize: 15,
                height: 1.35,
                color: mine ? GuidePalette.onAccent : GuidePalette.ink,
              ),
            ),
            if (onSpeak != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  key: speakKey,
                  tooltip: speakTip,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onSpeak,
                  icon: Icon(
                    speaking ? Icons.stop : Icons.volume_up,
                    size: 18,
                    color: GuidePalette.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila del menú del chat, con los colores, la fuente y los iconos de la guía.
class GuideMenuItem extends PopupMenuItem<String> {
  final bool checked;

  GuideMenuItem({
    super.key,
    required super.value,
    required IconData icon,
    required String label,
    this.checked = false,
  }) : super(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _GuideMenuRow(icon: icon, label: label, checked: checked),
        );
}

class _GuideMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool checked;

  const _GuideMenuRow({
    required this.icon,
    required this.label,
    required this.checked,
  });

  @override
  Widget build(BuildContext context) {
    final tone = checked ? GuidePalette.accent : GuidePalette.ink;
    return Row(
      children: [
        Icon(icon, color: tone, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppFonts.poppins(color: tone, fontSize: 15),
          ),
        ),
        if (checked)
          const Icon(Icons.check, color: GuidePalette.accent, size: 18)
        else
          const SizedBox(width: 18),
      ],
    );
  }
}
