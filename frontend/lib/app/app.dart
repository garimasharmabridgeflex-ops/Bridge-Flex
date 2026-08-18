import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics_service.dart';
import '../core/notifications/fcm_service.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class KFlexApp extends ConsumerStatefulWidget {
  const KFlexApp({super.key});

  @override
  ConsumerState<KFlexApp> createState() => _KFlexAppState();
}

class _KFlexAppState extends ConsumerState<KFlexApp> {
  bool _fcmInitialized = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Initialize FCM once the user is signed in and not yet initialized.
    ref.listen(authStateProvider, (_, next) {
      final user = next.valueOrNull;
      if (user != null && !_fcmInitialized) {
        _fcmInitialized = true;
        ref.read(fcmServiceProvider).init();
      } else if (user == null && _fcmInitialized) {
        _fcmInitialized = false;
        ref.read(fcmServiceProvider).unregister();
      }
      // Ties Analytics events (including automatic screen_view logging via
      // analyticsObserverProvider) to a user ID so "active users" reflects
      // real signed-in accounts, not just anonymous sessions.
      ref.read(analyticsProvider).setUserId(id: user?.uid);
    });

    return MaterialApp.router(
      title: 'KFlex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => InAppNotificationOverlay(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

