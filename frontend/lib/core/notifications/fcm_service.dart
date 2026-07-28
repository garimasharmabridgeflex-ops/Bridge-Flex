import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

// ─── Background handler (top-level, not in a class) ─────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized by the time this is called.
  // Nothing extra is needed here — the OS notification tray handles display.
}

// ─── Foreground message stream ───────────────────────────────────────────────

/// Emits every [RemoteMessage] received while the app is in the foreground.
/// Consumed by [InAppNotificationOverlay] to show banner alerts.
final foregroundMessageProvider = StreamProvider<RemoteMessage?>((ref) {
  return FirebaseMessaging.onMessage;
});

// ─── Service ─────────────────────────────────────────────────────────────────

class FcmService {
  FcmService(this._ref);
  final Ref _ref;

  /// Call once after the user is fully signed in. Requests permission, then
  /// registers/refreshes the FCM token with the backend.
  Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // 1. Request permission (iOS / macOS; Android 13+ also respects this).
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // 2. Register global background handler.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 3. Get the current token and register it.
      final token = await messaging.getToken();
      if (token != null) await _register(token);

      // 4. Re-register whenever the token rotates.
      messaging.onTokenRefresh.listen(_register);
    } catch (e) {
      // Local dev / emulator fallback: Google Play Services requires a real
      // production FCM API key in google-services.json to fetch native FCM tokens.
      // In local dev mode, in-app notifications operate directly via Firestore.
      debugPrint('FCM init skipped or unavailable in local mode: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _ref.read(notificationsRepositoryProvider).registerFcmToken(token);
    } catch (_) {
      // Non-fatal — the backend already handles duplicate registrations.
    }
  }

  /// Call on sign-out so the server stops delivering pushes to this device.
  Future<void> unregister() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _ref.read(notificationsRepositoryProvider).unregisterFcmToken(token);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) => FcmService(ref));

// ─── In-app overlay widget ────────────────────────────────────────────────────

/// Wrap your top-level [MaterialApp] or [Scaffold] body with this widget.
/// It listens to [foregroundMessageProvider] and slides in a dismissible
/// banner at the top of the screen for every foreground FCM message.
class InAppNotificationOverlay extends ConsumerStatefulWidget {
  const InAppNotificationOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppNotificationOverlay> createState() =>
      _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState
    extends ConsumerState<InAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  RemoteMessage? _current;
  Timer? _dismissTimer;
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _show(RemoteMessage msg) async {
    _dismissTimer?.cancel();
    setState(() => _current = msg);
    await _ctrl.forward(from: 0);
    _dismissTimer = Timer(const Duration(seconds: 5), _dismiss);
  }

  Future<void> _dismiss() async {
    _dismissTimer?.cancel();
    await _ctrl.reverse();
    if (mounted) setState(() => _current = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(foregroundMessageProvider, (_, next) {
      final msg = next.valueOrNull;
      if (msg != null) _show(msg);
    });

    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _fade,
                  child: _NotificationBanner(
                    message: _current!,
                    onDismiss: _dismiss,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Banner card ─────────────────────────────────────────────────────────────

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.message,
    required this.onDismiss,
  });

  final RemoteMessage message;
  final VoidCallback onDismiss;

  IconData get _icon {
    final type = message.data['type'] as String? ?? '';
    return switch (type) {
      'shift_booked' => Icons.event_available_rounded,
      'new_matching_shift' => Icons.campaign_rounded,
      'rating_received' => Icons.star_rounded,
      'shift_cancelled' => Icons.event_busy_rounded,
      _ => Icons.notifications_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String? ?? 'New notification';
    final body = notification?.body ?? message.data['body'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: 6,
        shadowColor: Colors.black26,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onDismiss,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  scheme.surface,
                  scheme.surface,
                ],
              ),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Icon badge
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Dismiss button
                IconButton(
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
