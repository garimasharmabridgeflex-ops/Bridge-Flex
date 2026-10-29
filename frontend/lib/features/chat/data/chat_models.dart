import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Maps a live `chatSessions/{id}` doc — the doc id plays the part the
  /// HTTP mirror injects as `sessionId`, and lastMessageAt is a Firestore
  /// Timestamp here. The server-created field is `lastShiftId` (the HTTP
  /// mirror exposes the raw doc, so `shiftId` reads empty there too).
  factory ChatSession.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final last = data['lastMessageAt'];
    return ChatSession(
      id: doc.id,
      shiftId: ((data['shiftId'] ?? data['lastShiftId']) as String?) ?? '',
      participantIds:
          (data['participantIds'] as List?)?.cast<String>() ?? const [],
      lastMessageAt: last is Timestamp
          ? last.toDate().toLocal()
          : DateTime.now(),
    );
  }
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

  /// Maps a live Firestore document. The HTTP mirror serialises createdAt as
  /// an RFC3339 string, but a snapshot carries a Firestore Timestamp, so the
  /// two factories deliberately differ.
  factory ChatMessage.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final created = data['createdAt'];
    return ChatMessage(
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: created is Timestamp
          ? created.toDate().toLocal()
          : created is String
              ? DateTime.parse(created).toLocal()
              : DateTime.now(),
    );
  }
}
