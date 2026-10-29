import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often server-backed screens refetch while the app is open.
const liveRefreshInterval = Duration(seconds: 15);

/// Foreground/background state of the app, kept up to date by
/// [AppLifecycleObserver] at the root of the widget tree — Riverpod has no
/// provider-native way to read it.
final appLifecycleStateProvider = StateProvider<AppLifecycleState>(
  (ref) => AppLifecycleState.resumed,
);

/// One heartbeat for the whole app.
///
/// Every provider that reads state over the function API `watch`es this and
/// therefore recomputes on each tick. Before this existed, those screens only
/// refetched on pull-to-refresh or after the user's own mutation, so a change
/// made elsewhere — an admin verifying a DBS check, a nursery approving an
/// applicant, an invoice being generated — stayed invisible until the app was
/// restarted or the account signed out and back in.
///
/// Firestore-backed screens (shift detail, notifications, chat) are NOT wired
/// to this: they already stream, and re-subscribing them every tick would be
/// pure waste.
///
/// The timer only runs while the app is in the foreground — a phone in
/// someone's pocket must not keep polling — and resuming jumps the queue with
/// an immediate tick, so coming back to the app never shows a stale screen for
/// a full interval.
final liveTickProvider = StreamProvider<int>((ref) {
  final controller = StreamController<int>();
  var tick = 0;
  Timer? timer;

  void start() => timer ??= Timer.periodic(liveRefreshInterval, (_) {
        controller.add(++tick);
      });
  void stop() {
    timer?.cancel();
    timer = null;
  }

  if (ref.read(appLifecycleStateProvider) == AppLifecycleState.resumed) {
    start();
  }

  ref.listen(appLifecycleStateProvider, (_, next) {
    if (next == AppLifecycleState.resumed) {
      controller.add(++tick);
      start();
    } else {
      stop();
    }
  });

  ref.onDispose(() {
    stop();
    controller.close();
  });

  return controller.stream;
});

/// Mirrors the OS lifecycle into [appLifecycleStateProvider].
///
/// Mounted once, above the router, so it also covers screens pushed on top of
/// the shell.
class AppLifecycleObserver extends ConsumerStatefulWidget {
  const AppLifecycleObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleObserver> createState() =>
      _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLifecycleStateProvider.notifier).state = state;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
