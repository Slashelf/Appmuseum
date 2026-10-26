import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/chat_controller.dart';
import '../chat/chat_message.dart';
import '../chat/chat_voice.dart';
import '../chat/guide_narrator.dart';
import '../chat/local_exhibition_answers.dart';
import '../core/locale/locale_controller.dart';
import '../core/theme/app_theme.dart';
import 'app_localizations.dart';
import 'beacon_scan_services.dart';
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

  final TextEditingController _input = TextEditingController();
  final TextEditingController _key = TextEditingController();
  final TextEditingController _eleven = TextEditingController();
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
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(ChatController.modeStorageKey) ==
          ChatAnswerMode.deepseek.name) {
        await chat.setMode(ChatAnswerMode.deepseek, persist: false);
      }
      final savedKey = prefs.getString(ChatController.keyStorageKey) ?? '';
      if (savedKey.isNotEmpty && _key.text.isEmpty) {
        _key.text = savedKey;
        chat.updateRuntimeKey(savedKey);
      }
      if (!chat.hasCompiledElevenKey) {
        final savedEleven = prefs.getString(ChatController.elevenKeyStorageKey) ?? '';
        if (savedEleven.isNotEmpty && _eleven.text.isEmpty) {
          _eleven.text = savedEleven;
          chat.elevenRuntimeKey = savedEleven;
        }
      }
      final savedVoice = prefs.getString(ChatController.elevenVoiceStorageKey) ?? '';
      if (savedVoice.isNotEmpty) chat.elevenVoiceId = savedVoice;
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
    _ownedSpeaker?.stop();
    _narrator?.stop();
    _input.dispose();
    _key.dispose();
    _eleven.dispose();
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
      _level = 0;
      await _ear.stop();
    }
    if (!mounted) return;
    setState(() => _sending = true);
    _input.clear();
    _heard = '';
    // A new line follows the bottom only when the visitor was already there.
    if (_followBottom) _revealBottom();
    await chat.submit(
      text,
      languageCode: language,
      noDataText: noData,
      aiUnavailableText: aiUnavailable,
      spoken: _conversation,
      onSentence: _conversation
          ? (sentence) {
              _guideNarrator().enqueue(
                sentence,
                languageCode: language,
                apiKey: () => chat.elevenKey,
                voiceId: () => chat.elevenVoiceId,
              );
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
    return narrator;
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

  Future<void> _startListen() async {
    if (_sending || _listening || _speakingIndex != null) return;
    if (!_micExplained) {
      final agreed = await _explainMic();
      if (!agreed || !mounted) return;
      _micExplained = true;
      await _saveBool(micExplainedKey, true);
    }
    if (!mounted) return;
    _textBeforeMic = _input.text;
    _heard = '';
    _ignoreFinish = false;
    final language = context.read<LocaleController>().locale.languageCode;
    final ready = await _ear.prepare(
      onStatus: _onListenStatus,
      onError: _onEarError,
    );
    if (!ready) {
      _notice('micUnavailable');
      return;
    }
    if (!mounted) return;
    setState(() {
      _listening = true;
      _level = 0;
    });
    try {
      await _ear.listen(
        onWords: _onWords,
        onLevel: _onLevel,
        localeId: _localeId(language),
      );
    } catch (_) {
      _listening = false;
      _restoreMicText();
      if (mounted) setState(() {});
      _notice('micUnavailable');
    }
  }

  Future<void> _finishListen() async {
    if (!_listening) return;
    try {
      await _ear.stop();
    } catch (_) {
      _onFinished();
    }
  }

  Future<void> _cancelListen() async {
    _ignoreFinish = true;
    _listening = false;
    _level = 0;
    _heard = '';
    _restoreMicText();
    if (mounted) setState(() {});
    try {
      await _ear.cancel();
    } catch (_) {}
  }

  Future<void> _toggleMic() async {
    if (_sending || _speakingIndex != null) return;
    if (_listening) {
      await _finishListen();
      return;
    }
    await _startListen();
  }

  Future<void> _beginHold() async {
    if (_listening || _sending || _speakingIndex != null) return;
    await _startListen();
  }

  Future<void> _endHold() async {
    if (!_listening) return;
    await _finishListen();
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
    _level = 0;
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
      _level = 0;
      await _ear.stop();
    }
    _thenListen = thenListen || _conversation;
    if (!mounted) return;
    setState(() => _speakingIndex = index);
    final language = context.read<LocaleController>().locale.languageCode;
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

  Widget _modeBar(AppLocalizations t, ChatController chat) {
    if (chat.hasCompiledKey) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _key,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        style: AppFonts.poppins(fontSize: 14),
        onChanged: chat.updateRuntimeKey,
        decoration: InputDecoration(
          hintText: t.get('chatKeyHint'),
          hintStyle: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
          filled: true,
          fillColor: GuidePalette.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: GuidePalette.accent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: GuidePalette.accent, width: 1.4),
          ),
        ),
      ),
    );
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
      ),
      body: Column(
        children: [
          _modeSwitch(t, chat),
          if (chat.mode == ChatAnswerMode.deepseek) _modeBar(t, chat),
          if (placeName != null && placeName.trim().isNotEmpty)
            Container(
              width: double.infinity,
              color: GuidePalette.background,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                t.get('chatHere').replaceAll('{name}', placeName),
                style: AppFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: GuidePalette.accent,
                ),
              ),
            ),
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
          else ...[
            _voiceChoices(t, chat),
            if (_conversation && !chat.hasCompiledElevenKey)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: TextField(
                  key: const Key('chat-eleven-key'),
                  controller: _eleven,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppFonts.poppins(fontSize: 14),
                  onChanged: chat.updateElevenField,
                  decoration: InputDecoration(
                    hintText: t.get('elevenKeyHint'),
                    hintStyle: AppFonts.poppins(fontSize: 13, color: GuidePalette.muted),
                  ),
                ),
              ),
            SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
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
                  if (_listening) ...[
                    const SizedBox(width: 6),
                    _MicBars(level: _level),
                    IconButton(
                      key: const Key('chat-mic-cancel'),
                      tooltip: t.get('micCancel'),
                      onPressed: _cancelListen,
                      icon: const Icon(Icons.close, color: GuidePalette.muted),
                    ),
                  ],
                  GestureDetector(
                    key: const Key('chat-mic'),
                    onTap: _sending || _speakingIndex != null ? null : _toggleMic,
                    onLongPressStart: _sending || _speakingIndex != null ? null : (_) => _beginHold(),
                    onLongPressEnd: (_) => _endHold(),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        color: _listening ? GuidePalette.accent : GuidePalette.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t.get('chatSend'),
                    onPressed: _sending ? null : () => _send(),
                    icon: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: GuidePalette.accent,
                            ),
                          )
                        : const Icon(Icons.send, color: GuidePalette.accent),
                  ),
                ],
              ),
            ),
          ),
          ],
        ],
      ),
    );
  }

  Widget _modeSwitch(AppLocalizations t, ChatController chat) {
    final local = chat.mode == ChatAnswerMode.local;
    Widget tab(String label, bool selected, Key key, ChatAnswerMode mode) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: selected ? GuidePalette.accent : GuidePalette.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                chat.setMode(mode);
                BeaconServiceFlutter().recoverScan();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? GuidePalette.onAccent : GuidePalette.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          tab(
            t.get('modeLocalLabel'),
            local,
            const Key('chat-mode-local'),
            ChatAnswerMode.local,
          ),
          tab(
            t.get('modeChatbotLabel'),
            !local,
            const Key('chat-mode-chatbot'),
            ChatAnswerMode.deepseek,
          ),
        ],
      ),
    );
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
          side: const BorderSide(color: GuidePalette.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Text(
          label,
          style: AppFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            button(
              t.get('localAskFounded'),
              LocalExhibitionQuestion.founded,
              const Key('chat-local-founded'),
            ),
            button(
              t.get('localAskImages'),
              LocalExhibitionQuestion.images,
              const Key('chat-local-images'),
            ),
            button(
              t.get('localAskVisit'),
              LocalExhibitionQuestion.visit,
              const Key('chat-local-visit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceChoices(AppLocalizations t, ChatController chat) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: _VoiceSwitch(
              label: t.get('micAutoSend'),
              value: _autoSend,
              switchKey: const Key('chat-auto-send'),
              onChanged: (value) {
                setState(() => _autoSend = value);
                _saveBool(autoSendKey, value);
              },
            ),
          ),
          Expanded(
            child: _VoiceSwitch(
              label: t.get('voiceToggle'),
              value: _conversation,
              switchKey: const Key('chat-voice'),
              onChanged: (value) {
                setState(() => _conversation = value);
                _saveBool(conversationKey, value);
                if (!value) _stopAudio();
              },
            ),
          ),
          TextButton(
            key: const Key('chat-stop-audio'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: _stopAudio,
            child: Text(t.get('voiceStop')),
          ),
          TextButton(
            key: const Key('chat-talk'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: () => _openVoice(chat),
            child: Text(t.get('voiceTalk')),
          ),
        ],
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
        builder: (_) => VoiceConversationScreen(
          ear: widget.ear,
          speaker: widget.speaker,
        ),
      ),
    );
  }
}

class _VoiceSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final Key switchKey;
  final ValueChanged<bool> onChanged;

  const _VoiceSwitch({
    required this.label,
    required this.value,
    required this.switchKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Switch(
          key: switchKey,
          value: value,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeThumbColor: GuidePalette.accent,
          onChanged: onChanged,
        ),
        Flexible(
          child: Text(
            label,
            style: AppFonts.poppins(fontSize: 11, color: GuidePalette.muted),
          ),
        ),
      ],
    );
  }
}

class _MicBars extends StatelessWidget {
  final double level;

  const _MicBars({required this.level});

  @override
  Widget build(BuildContext context) {
    const shape = [0.45, 0.7, 1.0, 0.75, 0.5];
    return Row(
      key: const Key('chat-mic-level'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final factor in shape)
          Container(
            width: 3,
            height: 6 + 16 * level * factor,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: GuidePalette.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
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
