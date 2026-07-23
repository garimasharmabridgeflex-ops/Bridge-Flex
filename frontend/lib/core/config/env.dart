import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Local dev topology: every HTTP-triggered Cloud Function runs as its own
/// process on a fixed port (see backend/services/*/run-local.sh — Go's
/// functions-framework serves one FUNCTION_TARGET per process, so there is
/// no single base URL locally, unlike a deployed Cloud Function per-service
/// URL). This map is the single source of truth for that local wiring.
enum ApiFunction {
  updateProfile(8101),
  getProfile(8102),
  getPublicProfile(8103),
  createShift(8104),
  updateShift(8105),
  listOpenShifts(8106),
  listMyShifts(8113),
  getShift(8107),
  acceptShift(8108),
  cancelShift(8109),
  markNoShow(8116),
  createRating(8110),
  createDocument(8111),
  reviewDocument(8112),
  getDocumentStatus(8114),
  listMyDocuments(8115),
  listPendingDocuments(8117),
  getPlatformStats(8140),
  listAllUsers(8141),
  getUserDetail(8142),
  setUserSuspended(8143),
  setVerificationBadge(8144),
  registerFcmToken(8121),
  unregisterFcmToken(8122),
  sendChatMessage(8123),
  listChatMessages(8124),
  listChatSessions(8127),
  listNotifications(8125),
  markNotificationRead(8126),
  markAllNotificationsRead(8128),
  createPayout(8093);

  const ApiFunction(this.localPort);
  final int localPort;
}

class Env {
  Env._();

  /// True while pointed at the Firebase Emulator Suite + local Go
  /// processes instead of a deployed project. Flip this (or wire it to
  /// --dart-define) once real Cloud Functions/Firebase are deployed.
  static const bool useLocalBackend = true;

  static const String firebaseProjectId = 'demo-bridgeflex';

  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8180;
  static const int storageEmulatorPort = 9199;

  /// Host to reach the dev machine from wherever the app is running.
  /// - Web: the app runs in the same browser sandbox, so `localhost` works.
  /// - Android emulator: `10.0.2.2` is the special alias for the host loopback.
  /// - Physical device / iOS simulator / desktop: override via
  ///   `--dart-define=DEV_HOST=<lan-ip>` since the device can't see `localhost`.
  static String get devHost {
    const override = String.fromEnvironment('DEV_HOST');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'localhost';
    if (!kIsWeb && Platform.isAndroid) return '10.0.2.2';
    return 'localhost';
  }

  static Uri functionUri(ApiFunction fn) =>
      Uri.parse('http://$devHost:${fn.localPort}');
}
