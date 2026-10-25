import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import 'notification_item.dart';

class NotificationsRepository {
  NotificationsRepository(this._api, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _firestore;

  /// Live Firestore snapshot stream of notifications for the signed-in user.
  /// Eliminates manual refresh requirement for shift approvals and timesheets.
  Stream<List<NotificationItem>> watchNotifications(String uid) {
    return _firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(NotificationItem.fromFirestore).toList());
  }

  /// Real-time stream of unread notification count.
  Stream<int> watchUnreadCount(String uid) {
    return watchNotifications(uid).map((list) => list.where((n) => !n.read).length);
  }

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
