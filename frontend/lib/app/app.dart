import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/fcm_service.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class BridgeFlexApp extends ConsumerStatefulWidget {
  const BridgeFlexApp({super.key});

  @override
  ConsumerState<BridgeFlexApp> createState() => _BridgeFlexAppState();
}

class _BridgeFlexAppState extends ConsumerState<BridgeFlexApp> {
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
    });

    return MaterialApp.router(
      title: 'K Vision',
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

