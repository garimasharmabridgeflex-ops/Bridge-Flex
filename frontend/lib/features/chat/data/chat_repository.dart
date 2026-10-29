import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import 'chat_models.dart';

class ChatRepository {
  ChatRepository(this._api, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _firestore;

  /// Plain HTTP rather than a live Firestore query — see the note on
  /// shift_repository.dart's fetchOpenShifts for why.
  Future<List<ChatSession>> fetchSessions() async {
    final res = await _api.post(ApiFunction.listChatSessions);
    final raw = (res['sessions'] as List?) ?? const [];
    final sessions =
        raw.cast<Map<String, dynamic>>().map(ChatSession.fromJson).toList();
    sessions.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return sessions;
  }

  /// Live stream of the caller's sessions — the same client-legal
  /// `array-contains` query listChatSessions runs server-side, sorted
  /// client-side by lastMessageAt for the same reason the HTTP mirror skips
  /// orderBy (no composite index deployed for it).
  ///
  /// The HTTP fetch in [foldSessions] is deliberately still kicked once when
  /// the list opens: that call runs foldDuplicateSessions server-side, which
  /// migrates any legacy per-shift threads into the canonical pair thread.
  /// The stream then reflects the merge the moment those docs are deleted.
  Stream<List<ChatSession>> watchSessions(String uid) {
    return _firestore
        .collection('chatSessions')
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final sessions = snap.docs.map(ChatSession.fromFirestore).toList();
      sessions.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      return sessions;
    });
  }

  /// Fire-and-forget legacy-thread fold; see [watchSessions].
  Future<void> foldSessions() async => fetchSessions();

  Future<List<ChatMessage>> fetchMessages(String sessionId) async {
    final res = await _api.postWithQuery(
      ApiFunction.listChatMessages,
      query: {'sessionId': sessionId},
    );
    final raw = (res['messages'] as List?) ?? const [];
    return raw.cast<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
  }

  /// Live Firestore stream of a thread's messages in the same oldest-first
  /// order listChatMessages returns. Reading a message list only requires
  /// being a participant of the parent session (rules evaluate that with a
  /// get() on the session doc, not from the query), and createdAt is a
  /// single-field order so no composite index is involved.
  ///
  /// This replaces the 4-second invalidate loop that used to run while a
  /// thread was open: a message from the other side, or the caller's own send,
  /// now lands the moment the server writes it.
  Stream<List<ChatMessage>> watchMessages(String sessionId) {
    return _firestore
        .collection('chatSessions')
        .doc(sessionId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromFirestore).toList());
  }

  Future<void> sendMessage({required String sessionId, required String text}) {
    return _api.post(ApiFunction.sendChatMessage, body: {
      'sessionId': sessionId,
      'text': text,
    });
  }
}
