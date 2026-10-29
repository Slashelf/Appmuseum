import 'chat_message.dart';

/// Conversación del visitante. Hoy está en memoria.
/// Otra implementación puede guardarla en SQLite o en una API.
abstract class ConversationStore {
  List<ChatMessage> get messages;

  void add(ChatMessage message);

  void clear();
}

class MemoryConversationStore implements ConversationStore {
  final List<ChatMessage> _messages = [];

  @override
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  @override
  void add(ChatMessage message) {
    _messages.add(message);
  }

  @override
  void clear() {
    _messages.clear();
  }
}
