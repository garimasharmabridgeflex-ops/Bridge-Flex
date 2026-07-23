import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import 'notification_item.dart';

class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  Future<List<NotificationItem>> list() async {
    final res = await _api.post(ApiFunction.listNotifications);
    final raw = (res['notifications'] as List?) ?? const [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(NotificationItem.fromJson)
        .toList();
  }

  Future<void> markRead(String notificationId) => _api.post(
        ApiFunction.markNotificationRead,
        body: {'notificationId': notificationId},
      );

  Future<void> markAllRead() => _api.post(ApiFunction.markAllNotificationsRead);

  Future<void> registerFcmToken(String token) =>
      _api.post(ApiFunction.registerFcmToken, body: {'token': token});

  Future<void> unregisterFcmToken(String token) =>
      _api.post(ApiFunction.unregisterFcmToken, body: {'token': token});
}
