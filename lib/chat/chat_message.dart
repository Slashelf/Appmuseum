enum ChatRole { visitor, guide }

class ChatMessage {
  final ChatRole role;
  final String text;

  const ChatMessage({required this.role, required this.text});

  const ChatMessage.visitor(this.text) : role = ChatRole.visitor;

  const ChatMessage.guide(this.text) : role = ChatRole.guide;
}
