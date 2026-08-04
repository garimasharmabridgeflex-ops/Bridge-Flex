// Drives the app through its main screens on a simulator and captures a
// screenshot of each, at the simulator's native resolution — so App Store
// screenshots can be produced in CI without owning the device.
//
// Run via .github/workflows/ios_screenshots.yml, or locally on a Mac:
//   flutter drive \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/screenshots_test.dart \
//     -d <simulator-udid> \
//     --dart-define=USE_LOCAL_BACKEND=false --dart-define=PROJECT_ID=kvision-503115
//
// Signs in with the seeded demo staff account (backend/seed/demo) so the
// screens have real content rather than empty states.
//
// Every step is individually guarded: a selector that fails to match logs a
// warning and moves on rather than aborting the run, so one changed label
// still yields a usable set of screenshots instead of nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bridgeflex_app/main.dart' as app;

const _email = 'afrilexkenya+demo.staff@gmail.com';
const _password = 'BridgeFlexDemo2026!';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture App Store screenshots', (tester) async {
    app.main();

    // Firebase init, Remote Config fetch and the auth state check all happen
    // on first frame; pumpAndSettle alone races them.
    await _settle(tester, seconds: 12);

    var shot = 0;
    Future<void> capture(String name) async {
      shot++;
      final label = '${shot.toString().padLeft(2, '0')}-$name';
      await binding.takeScreenshot(label);
      debugPrint('SCREENSHOT captured: $label');
    }

    await capture('sign-in');

    // ── Sign in ───────────────────────────────────────────────────────────
    // Fields are located by type and position rather than by label text:
    // AppTextField renders a floating label, so the label may or may not be
    // in the tree as matchable text depending on focus state.
    final fields = find.byType(TextField);
    if (tester.any(fields) && fields.evaluate().length >= 2) {
      await tester.enterText(fields.at(0), _email);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(fields.at(1), _password);
      await tester.pump(const Duration(milliseconds: 300));
      await _tapText(tester, 'Sign in');
      await _settle(tester, seconds: 15);
      await capture('home');
    } else {
      debugPrint('WARNING: sign-in fields not found — already signed in?');
      await capture('home');
    }

    // ── Bottom navigation tabs ────────────────────────────────────────────
    // Tapped by ICON, not label: floating_nav_bar.dart only renders the label
    // for the currently selected tab, so find.text('Messages') never matches
    // while some other tab is active. Icons are the unselected variants from
    // home_shell.dart. Training is skipped — not a shift-flow screen, so it
    // adds nothing to a store listing.
    final tabs = <String, IconData>{
      'my-shifts': Icons.event_note_outlined,
      'messages': Icons.chat_bubble_outline_rounded,
      'profile': Icons.person_outline_rounded,
    };
    for (final entry in tabs.entries) {
      if (await _tapIcon(tester, entry.value)) {
        await _settle(tester, seconds: 6);
        await capture(entry.key);
      }
    }

    // ── Shift detail ──────────────────────────────────────────────────────
    // Back to Browse, then open a shift: its detail screen is the most
    // informative single screen in the app for a store listing.
    if (await _tapIcon(tester, Icons.search_outlined)) {
      await _settle(tester, seconds: 8);
      for (final title in ['Morning cover', 'Full day', 'Afternoon cover', 'cover']) {
        if (await _tapTextContaining(tester, title)) {
          await _settle(tester, seconds: 8);
          await capture('shift-detail');
          break;
        }
      }
    }

    debugPrint('SCREENSHOTS done: $shot captured');
  });
}

/// pumpAndSettle throws if animations never quiesce — this app runs looping
/// shimmer placeholders while data loads, which is exactly that case. Pump
/// fixed frames instead.
Future<void> _settle(WidgetTester tester, {required int seconds}) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<bool> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (!tester.any(finder)) {
    debugPrint('WARNING: no widget with text "$text" — skipping');
    return false;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  return true;
}

Future<bool> _tapIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  if (!tester.any(finder)) {
    debugPrint('WARNING: no icon $icon on screen — skipping');
    return false;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  return true;
}

Future<bool> _tapTextContaining(WidgetTester tester, String substring) async {
  final finder = find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').contains(substring),
  );
  if (!tester.any(finder)) {
    debugPrint('WARNING: no text containing "$substring" — skipping');
    return false;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  return true;
}
