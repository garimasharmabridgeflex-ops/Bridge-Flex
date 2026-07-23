class ChatSession {
  const ChatSession({
    required this.id,
    required this.shiftId,
    required this.participantIds,
    required this.lastMessageAt,
  });

  final String id;
  final String shiftId;
  final List<String> participantIds;
  final DateTime lastMessageAt;

  String otherParticipant(String selfUid) =>
      participantIds.firstWhere((id) => id != selfUid, orElse: () => '');

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['sessionId'] as String,
        shiftId: json['shiftId'] as String? ?? '',
        participantIds: (json['participantIds'] as List?)?.cast<String>() ?? const [],
        lastMessageAt: json['lastMessageAt'] != null
            ? DateTime.parse(json['lastMessageAt'] as String).toLocal()
            : DateTime.now(),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.senderId,
    required this.text,
    required this.createdAt,
  });

  final String senderId;
  final String text;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        senderId: json['senderId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String).toLocal()
            : DateTime.now(),
      );
}
