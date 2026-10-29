import 'package:bridgeflex_app/core/live/live_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the heartbeat ticks while resumed and pauses in the background',
      (tester) async {
    final container = ProviderContainer();

    final ticks = <int>[];
    container.listen(liveTickProvider, (_, next) => next.whenData(ticks.add));

    // Foreground: one tick per interval, which is what makes every provider
    // watching it refetch server state.
    await tester.pump(liveRefreshInterval);
    await tester.pump(liveRefreshInterval);
    expect(ticks, [1, 2]);

    // Backgrounded: the timer stops, so a phone in a pocket is not polling.
    container.read(appLifecycleStateProvider.notifier).state =
        AppLifecycleState.paused;
    await tester.pump(liveRefreshInterval);
    await tester.pump(liveRefreshInterval);
    expect(ticks, [1, 2]);

    // Resuming jumps the queue with an immediate tick, so coming back to the
    // app does not show a stale screen for a whole interval.
    container.read(appLifecycleStateProvider.notifier).state =
        AppLifecycleState.resumed;
    await tester.pump();
    expect(ticks, [1, 2, 3]);
    await tester.pump(liveRefreshInterval);
    expect(ticks, [1, 2, 3, 4]);

    // Disposing the container stops the timer; leaving it running would fail
    // the test framework's pending-timer check.
    container.dispose();
  });
}
