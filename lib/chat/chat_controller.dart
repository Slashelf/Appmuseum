import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/object_model.dart';
import 'chat_faq.dart';
import 'chat_message.dart';
import 'conversation_store.dart';
import 'guide_answer_service.dart';
import 'knowledge_source.dart';
import 'local_exhibition_answers.dart';
import 'remote_guide_answer_service.dart';
import 'visit_context.dart';

enum ChatAnswerMode { local, deepseek }

/// Une el idioma, el lugar del beacon, la búsqueda y el modo elegido.
/// Cambiar de lugar no borra los mensajes ni abre el chat.
class ChatController extends ChangeNotifier {
  static const modeStorageKey = 'chat_answer_mode';
  static const keyStorageKey = 'deepseek_api_key';
  static const elevenKeyStorageKey = 'elevenlabs_api_key';
  static const elevenVoiceStorageKey = 'elevenlabs_voice_id';

  final ConversationStore store;
  final KnowledgeSource knowledge;
  final GuideAnswerService answers;
  final RemoteGuideAnswerService? remote;
  final VisitContext visit;
  final String compiledKey;
  final String compiledElevenKey;

  ChatAnswerMode _mode = ChatAnswerMode.local;
  String runtimeKey = '';
  String elevenRuntimeKey = '';
  String elevenVoiceId = '';
  bool tookOffline = false;

  ChatController({
    required this.store,
    required this.knowledge,
    required this.answers,
    required this.visit,
    this.remote,
    this.compiledKey = '',
    this.compiledElevenKey = '',
  }) {
    visit.addListener(_onVisit);
    if (compiledKey.trim().isNotEmpty) {
      remote?.apiKey = compiledKey.trim();
    }
  }

  List<ChatMessage> get messages => store.messages;

  ChatAnswerMode get mode => _mode;

  bool get hasCompiledKey => compiledKey.trim().isNotEmpty;

  bool get hasCompiledElevenKey => compiledElevenKey.trim().isNotEmpty;

  /// Clave de ElevenLabs. No se escribe en registros.
  String get elevenKey {
    if (hasCompiledElevenKey) return compiledElevenKey.trim();
    return elevenRuntimeKey.trim();
  }

  void _onVisit() {
    notifyListeners();
  }

  Future<void> setMode(ChatAnswerMode value, {bool persist = true}) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    if (!persist) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(modeStorageKey, value.name);
    } catch (_) {}
  }

  void updateRuntimeKey(String value) {
    runtimeKey = value.trim();
    if (!hasCompiledKey) {
      remote?.apiKey = runtimeKey;
    }
    _saveKey(runtimeKey);
  }

  void updateElevenField(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      elevenRuntimeKey = '';
      _savePref(elevenKeyStorageKey, '');
      return;
    }
    if (trimmed.startsWith('sk')) {
      elevenRuntimeKey = trimmed;
      _savePref(elevenKeyStorageKey, trimmed);
      return;
    }
    if (trimmed.length >= 15) {
      elevenVoiceId = trimmed;
      _savePref(elevenVoiceStorageKey, trimmed);
    }
  }

  Future<void> _saveKey(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value.isEmpty) {
        await prefs.remove(keyStorageKey);
      } else {
        await prefs.setString(keyStorageKey, value);
      }
    } catch (_) {}
  }

  Future<void> _savePref(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    } catch (_) {}
  }

  /// Un reconocedor de voz futuro puede llamar a este mismo método.
  Future<void> submit(
    String question, {
    required String languageCode,
    required String noDataText,
    String aiUnavailableText = '',
    bool spoken = false,
    bool fromVoice = false,
    int dialogueLimit = RemoteGuideAnswerService.maxDialogueMessages,
    void Function(String sentence)? onSentence,
  }) async {
    tookOffline = false;
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;
    store.add(ChatMessage.visitor(trimmed));
    notifyListeners();

    if (_mode == ChatAnswerMode.local) {
      store.add(ChatMessage.guide(LocalExhibitionAnswers.onlyButtons(languageCode)));
      notifyListeners();
      return;
    }

    if (ChatFaq.isSpam(trimmed) || ChatFaq.isOffTopic(trimmed)) {
      store.add(ChatMessage.guide(ChatFaq.offTopicReply(languageCode)));
      notifyListeners();
      return;
    }

    final snippets = await knowledge.search(
      question: trimmed,
      languageCode: languageCode,
      currentPlaceId: visit.place?.id,
    );
    final reply = await _reply(
      question: trimmed,
      languageCode: languageCode,
      snippets: snippets,
      noDataText: noDataText,
      aiUnavailableText: aiUnavailableText,
      spoken: spoken,
      dialogueLimit: dialogueLimit,
      onSentence: onSentence,
    );
    if (fromVoice && tookOffline) {
      notifyListeners();
      return;
    }
    store.add(ChatMessage.guide(reply));
    notifyListeners();
  }

  Future<String> _reply({
    required String question,
    required String languageCode,
    required List<KnowledgeSnippet> snippets,
    required String noDataText,
    required String aiUnavailableText,
    required bool spoken,
    required int dialogueLimit,
    required void Function(String sentence)? onSentence,
  }) async {
    if (remote == null) return ChatFaq.cannotDraft(languageCode);
    String? remoteReply;
    try {
      if (spoken) {
        remoteReply = await remote!.tryAskSpoken(
          question: question,
          languageCode: languageCode,
          snippets: snippets,
          noDataText: noDataText,
          history: store.messages,
          placeName: _placeName(languageCode),
          dialogueLimit: dialogueLimit,
          onSentence: onSentence ?? (_) {},
        );
      } else {
        remoteReply = await remote!.tryAsk(
          question: question,
          languageCode: languageCode,
          snippets: snippets,
          noDataText: noDataText,
          history: store.messages,
          placeName: _placeName(languageCode),
        );
      }
    } catch (error) {
      if (_isOffline(error)) tookOffline = true;
      remoteReply = null;
    }
    if (remoteReply != null && remoteReply.trim().isNotEmpty) {
      return remoteReply.trim();
    }
    return ChatFaq.cannotDraft(languageCode);
  }

  bool _isOffline(Object error) {
    return error is SocketException ||
        error is HandshakeException ||
        error is TlsException ||
        error is TimeoutException;
  }

  /// Respuesta guardada de la exhibición actual. No llama a la red.
  Future<void> askStored(
    LocalExhibitionQuestion question, {
    required String languageCode,
    required String label,
  }) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    store.add(ChatMessage.visitor(trimmed));
    store.add(
      ChatMessage.guide(
        LocalExhibitionAnswers.reply(
          question: question,
          place: visit.place,
          languageCode: languageCode,
        ),
      ),
    );
    notifyListeners();
  }

  String _placeName(String languageCode) {
    final ObjectModel? place = visit.place;
    if (place == null) return '';
    final text = place.localized(languageCode);
    final name = text.name.trim().isNotEmpty ? text.name.trim() : text.name2.trim();
    return name;
  }

  @override
  void dispose() {
    visit.removeListener(_onVisit);
    super.dispose();
  }
}
