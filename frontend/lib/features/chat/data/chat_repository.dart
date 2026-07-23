import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import 'chat_models.dart';

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

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

  Future<List<ChatMessage>> fetchMessages(String sessionId) async {
    final res = await _api.postWithQuery(
      ApiFunction.listChatMessages,
      query: {'sessionId': sessionId},
    );
    final raw = (res['messages'] as List?) ?? const [];
    return raw.cast<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
  }

  Future<void> sendMessage({required String sessionId, required String text}) {
    return _api.post(ApiFunction.sendChatMessage, body: {
      'sessionId': sessionId,
      'text': text,
    });
  }
}
