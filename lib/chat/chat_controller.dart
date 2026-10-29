import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/object_model.dart';
import 'chat_faq.dart';
import 'chat_message.dart';
import 'conversation_store.dart';
import 'connection_check.dart';
import 'guide_answer_service.dart';
import 'guide_secrets.dart';
import 'knowledge_source.dart';
import 'local_exhibition_answers.dart';
import 'remote_guide_answer_service.dart';
import 'spanish_narrator.dart';
import 'visit_context.dart';
import 'visit_memory.dart';

enum ChatAnswerMode { local, deepseek }

/// Une el idioma, el lugar del beacon, la búsqueda y el modo elegido.
/// Cambiar de lugar no borra los mensajes ni abre el chat.
class ChatController extends ChangeNotifier {
  static const modeStorageKey = 'chat_answer_mode';
  static const keyStorageKey = 'xai_api_key';
  static const legacyKeyStorageKey = 'deepseek_api_key';
  static const elevenKeyStorageKey = 'elevenlabs_api_key';
  static const elevenVoiceStorageKey = 'elevenlabs_voice_id';
  static const micLanguageStorageKey = 'chat_mic_language';

  final ConversationStore store;
  final KnowledgeSource knowledge;
  final GuideAnswerService answers;
  final RemoteGuideAnswerService? remote;
  final VisitContext visit;
  final String compiledKey;
  final String compiledElevenKey;
  final GuideSecretStore secrets;
  final ConnectionChecker connections;
  final NarratorVoiceSource? voices;

  ChatAnswerMode _mode = ChatAnswerMode.local;
  String runtimeKey = '';
  String elevenRuntimeKey = '';
  String elevenVoiceId = '';
  String micLanguage = 'auto';
  bool tookOffline = false;
  bool _restored = false;
  final VisitMemory _memory = VisitMemory();

  ChatController({
    required this.store,
    required this.knowledge,
    required this.answers,
    required this.visit,
    this.remote,
    this.compiledKey = '',
    this.compiledElevenKey = '',
    GuideSecretStore? secrets,
    ConnectionChecker? connections,
    this.voices,
  })  : secrets = secrets ?? MemoryGuideSecretStore(),
        connections = connections ?? HttpConnectionChecker() {
    visit.addListener(_onVisit);
    final current = visit.place;
    _memory.rememberPlace(current?.id, current?.name ?? '', store.messages);
    if (compiledKey.trim().isNotEmpty) {
      remote?.apiKey = compiledKey.trim();
    }
  }

  List<ChatMessage> get messages => store.messages;

  ChatAnswerMode get mode => _mode;

  bool get hasCompiledKey => compiledKey.trim().isNotEmpty;

  bool get hasCompiledElevenKey => compiledElevenKey.trim().isNotEmpty;

  /// Clave de DeepSeek que se usa de verdad. La compilada gana.
  String get deepSeekKey {
    if (hasCompiledKey) return compiledKey.trim();
    return runtimeKey.trim();
  }

  /// La misma clave de Grok sirve para el texto y para la voz.
  String get speechKey => deepSeekKey;

  /// `ara` por defecto. `leo` si el visitante eligió la voz de hombre.
  String get guideVoice => elevenVoiceId.trim() == 'leo' ? 'leo' : 'ara';

  /// Clave de ElevenLabs. No se envía a xAI.
  String get elevenKey {
    if (hasCompiledElevenKey) return compiledElevenKey.trim();
    return elevenRuntimeKey.trim();
  }

  /// Copia las claves viejas de SharedPreferences y las borra de ahí.
  Future<void> restoreSaved() async {
    if (_restored) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(modeStorageKey);
      if (savedMode == ChatAnswerMode.deepseek.name || savedMode == 'grok') {
        _mode = ChatAnswerMode.deepseek;
      } else if (savedMode == ChatAnswerMode.local.name) {
        _mode = ChatAnswerMode.local;
      }
      final savedMic = prefs.getString(micLanguageStorageKey) ?? 'auto';
      if (const {'auto', 'es', 'en', 'pt'}.contains(savedMic)) {
        micLanguage = savedMic;
      }
      await _dropLegacyKey();
      final deep = await _migrate(keyStorageKey);
      final eleven = await _migrate(elevenKeyStorageKey);
      final voice = await _migrate(elevenVoiceStorageKey);
      if (deep.isNotEmpty) runtimeKey = deep;
      if (eleven.isNotEmpty) elevenRuntimeKey = eleven;
      if (voice.isNotEmpty) elevenVoiceId = voice;
      if (!hasCompiledKey && runtimeKey.isNotEmpty) {
        remote?.apiKey = runtimeKey;
      }
      _restored = true;
      notifyListeners();
    } catch (_) {}
  }

  /// La clave vieja de DeepSeek no se manda a xAI.
  Future<void> _dropLegacyKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(legacyKeyStorageKey)) {
      await prefs.remove(legacyKeyStorageKey);
    }
    final leftover = (await secrets.read(legacyKeyStorageKey) ?? '').trim();
    if (leftover.isNotEmpty) {
      await secrets.write(legacyKeyStorageKey, null);
    }
  }

  Future<String> _migrate(String key) async {
    final current = (await secrets.read(key) ?? '').trim();
    final prefs = await SharedPreferences.getInstance();
    final old = (prefs.getString(key) ?? '').trim();
    if (current.isEmpty && old.isNotEmpty) {
      await secrets.write(key, old);
    }
    if (prefs.containsKey(key)) {
      await prefs.remove(key);
    }
    if (current.isNotEmpty) return current;
    return old;
  }

  void _onVisit() {
    final place = visit.place;
    _memory.rememberPlace(place?.id, place?.name ?? '', store.messages);
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

  void updateDeepSeekKey(String value) {
    if (hasCompiledKey) return;
    runtimeKey = value.trim();
    remote?.apiKey = runtimeKey;
    _saveSecret(keyStorageKey, runtimeKey);
  }

  void updateElevenKey(String value) {
    if (hasCompiledElevenKey) return;
    elevenRuntimeKey = value.trim();
    _saveSecret(elevenKeyStorageKey, elevenRuntimeKey);
  }

  /// Guarda lo que el modo hablar ya dijo, sin volver a llamar al modelo de texto.
  void rememberExchange(String question, String answer) {
    final asked = question.trim();
    final reply = answer.trim();
    if (asked.isNotEmpty) store.add(ChatMessage.visitor(asked));
    if (reply.isNotEmpty) store.add(ChatMessage.guide(reply));
    if (asked.isEmpty && reply.isEmpty) return;
    notifyListeners();
  }

  void updateVoiceId(String value) {
    final next = value.trim();
    if (next == elevenVoiceId) return;
    elevenVoiceId = next;
    notifyListeners();
    _saveSecret(elevenVoiceStorageKey, elevenVoiceId);
  }

  /// Idioma de la respuesta y de la voz. El micrófono manda; Automático sigue la interfaz.
  String replyLanguage(String uiLanguage) {
    switch (micLanguage) {
      case 'es':
      case 'en':
      case 'pt':
        return micLanguage;
      default:
        final code = uiLanguage.trim().toLowerCase();
        if (code == 'en' || code == 'de' || code == 'es') return code;
        return 'es';
    }
  }

  /// Locale del reconocedor: `es_ES`, `en_US`, `pt_BR` o `de_DE`.
  String earLocale(String uiLanguage) {
    switch (replyLanguage(uiLanguage)) {
      case 'en':
        return 'en_US';
      case 'pt':
        return 'pt_BR';
      case 'de':
        return 'de_DE';
      default:
        return 'es_ES';
    }
  }

  /// Voz de Grok ya elegida. No consulta otra red.
  Future<String> ensureNarratorVoice() async => guideVoice;

  /// Las mismas instrucciones del chat, con la exhibición que el beacon tiene ahora.
  Future<String> voiceInstructions(String languageCode) async {
    final speech = replyLanguage(languageCode);
    final snippets = await knowledge.search(
      question: visit.place?.name ?? '',
      languageCode: speech,
      currentPlaceId: visit.place?.id,
    );
    return RemoteGuideAnswerService.instructionsFor(
      languageCode: speech,
      snippets: snippets,
      placeName: _placeName(speech),
      summary: _memory.text,
    );
  }

  Future<void> setMicLanguage(String value) async {
    const allowed = {'auto', 'es', 'en', 'pt'};
    final next = allowed.contains(value) ? value : 'auto';
    if (micLanguage == next) return;
    micLanguage = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(micLanguageStorageKey, next);
    } catch (_) {}
  }

  void clearConversation() {
    store.clear();
    _memory.forgetDialogue();
    notifyListeners();
  }

  Future<void> _saveSecret(String key, String value) async {
    try {
      await secrets.write(key, value);
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

    if (ChatFaq.isSpam(trimmed)) {
      _sayLocal(ChatFaq.offTopicReply(languageCode), onSentence);
      return;
    }
    if (ChatFaq.isJoke(trimmed)) {
      _sayLocal(ChatFaq.jokeReply(languageCode, trimmed), onSentence);
      return;
    }
    if (ChatFaq.asksCurrentExhibition(trimmed) && visit.place == null) {
      _sayLocal(ChatFaq.noExhibitionReply(languageCode), onSentence);
      return;
    }
    if (ChatFaq.isOffTopic(trimmed)) {
      _sayLocal(ChatFaq.offTopicReply(languageCode), onSentence);
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

  void _sayLocal(String reply, void Function(String sentence)? onSentence) {
    store.add(ChatMessage.guide(reply));
    notifyListeners();
    onSentence?.call(reply);
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
    if (remote!.apiKey.trim().isEmpty) return ChatFaq.missingKey(languageCode);
    _memory.roll(store.messages, dialogueLimit);
    final start = _memory.boundary.clamp(0, store.messages.length);
    final history = store.messages.sublist(start);
    final summary = _memory.text;
    final placeName = _placeName(languageCode);
    final replyCode = replyLanguage(languageCode);
    String? remoteReply;
    try {
      if (spoken) {
        remoteReply = await remote!.tryAskSpoken(
          question: question,
          languageCode: replyCode,
          snippets: snippets,
          noDataText: noDataText,
          history: history,
          placeName: placeName,
          summary: summary,
          dialogueLimit: dialogueLimit,
          onSentence: onSentence ?? (_) {},
        );
      } else {
        remoteReply = await remote!.tryAsk(
          question: question,
          languageCode: replyCode,
          snippets: snippets,
          noDataText: noDataText,
          history: history,
          placeName: placeName,
          summary: summary,
        );
      }
    } catch (error) {
      debugPrint('DeepSeek: ${DeepSeekLog.safe('$error', remote!.apiKey)}');
      if (error is DeepSeekException && error.credit) {
        return ChatFaq.noCredit(languageCode);
      }
      if (error is DeepSeekException) {
        final shown = RemoteGuideAnswerService.visibleError(
          error.status,
          DeepSeekLog.safe(error.detail, remote!.apiKey),
        );
        if (shown.isNotEmpty) return shown;
      }
      if (_isOffline(error)) tookOffline = true;
      return ChatFaq.couldNotConnect(languageCode);
    }
    if (remoteReply == null) return ChatFaq.missingKey(languageCode);
    if (remoteReply.trim().isEmpty) return ChatFaq.couldNotConnect(languageCode);
    return remoteReply.trim();
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
