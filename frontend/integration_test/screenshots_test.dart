// Drives the app through every screen a signed-in staff member can reach and
// captures a screenshot of each, at the simulator's native resolution — so App
// Store screenshots can be produced in CI without owning the device.
//
// Run via .github/workflows/ios_screenshots.yml, or locally on a Mac:
//   flutter drive \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/screenshots_test.dart \
//     -d <simulator-udid> \
//     --dart-define=USE_LOCAL_BACKEND=false --dart-define=PROJECT_ID=kvision-503115
//
// The screen SIZE is fixed entirely by which simulator the workflow boots
// (default: iPhone 16 Pro Max → 1320x2868). binding.takeScreenshot captures
// the simulator's native framebuffer, so every screen here comes out at that
// same size — do not change the device in the workflow if the size must match
// the previous batch.
//
// Signs in with the seeded demo staff account (backend/seed/demo) so the
// screens have real content rather than empty states.
//
// Every step is individually guarded: a selector that fails to match logs a
// warning and moves on rather than aborting the run, so one changed label or a
// missing bit of demo data still yields a usable set of screenshots instead of
// nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bridgeflex_app/main.dart' as app;

const _email = 'afrilexkenya+demo.staff@gmail.com';
const _password = 'BridgeFlexDemo2026!';

// Bottom-nav tabs are tapped by ICON, not label: floating_nav_bar.dart only
// renders the label for the currently selected tab, so find.text('Messages')
// never matches while another tab is active. Icons are the unselected variants
// from home_shell.dart.
const _browseIcon = Icons.search_outlined;
const _myShiftsIcon = Icons.event_note_outlined;
const _messagesIcon = Icons.chat_bubble_outline_rounded;
const _trainingIcon = Icons.school_outlined;
const _profileIcon = Icons.person_outline_rounded;

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

    // ── 1. Sign in ─────────────────────────────────────────────────────────
    await capture('sign-in');

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
    } else {
      debugPrint('WARNING: sign-in fields not found — already signed in?');
    }

    // ── 2. Browse shifts (staff landing tab) ───────────────────────────────
    // Ensure we're on the Browse tab regardless of where auth left us.
    await _tapIcon(tester, _browseIcon);
    await _settle(tester, seconds: 6);
    await capture('browse');

    // ── 3. Shift detail ────────────────────────────────────────────────────
    // The most informative single screen in the app for a store listing.
    if (await _tapFirstText(
      tester,
      ['Morning cover', 'Full day', 'Afternoon cover', 'cover', 'shift'],
    )) {
      await _settle(tester, seconds: 8);
      await capture('shift-detail');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }

    // ── 4. My shifts ───────────────────────────────────────────────────────
    if (await _tapIcon(tester, _myShiftsIcon)) {
      await _settle(tester, seconds: 6);
      await capture('my-shifts');
    }

    // ── 5. Notifications ───────────────────────────────────────────────────
    // The bell (NotificationIconButton) lives in the Browse/My-shifts app bar,
    // so capture it while one of those tabs is showing.
    if (await _tapIcon(tester, Icons.notifications_outlined)) {
      await _settle(tester, seconds: 6);
      await capture('notifications');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }

    // ── 6. Messages (chat list) ────────────────────────────────────────────
    if (await _tapIcon(tester, _messagesIcon)) {
      await _settle(tester, seconds: 6);
      await capture('messages');

      // ── 7. Chat conversation ─────────────────────────────────────────────
      if (await _tapFirstOfType<ListTile>(tester)) {
        await _settle(tester, seconds: 6);
        await capture('chat');
        await _goBack(tester);
        await _settle(tester, seconds: 4);
      }
    }

    // ── 8. Training ────────────────────────────────────────────────────────
    if (await _tapIcon(tester, _trainingIcon)) {
      await _settle(tester, seconds: 6);
      await capture('training');

      // ── 9. Training module ───────────────────────────────────────────────
      // Module rows are InkWell-wrapped _ModuleCards; the first tappable
      // InkWell on this screen opens a module.
      if (await _tapFirstOfType<InkWell>(tester)) {
        await _settle(tester, seconds: 6);
        await capture('training-module');
        await _goBack(tester);
        await _settle(tester, seconds: 4);
      }
    }

    // ── 10. Profile ────────────────────────────────────────────────────────
    if (await _tapIcon(tester, _profileIcon)) {
      await _settle(tester, seconds: 6);
      await capture('profile');

      // ── 11. Edit profile ─────────────────────────────────────────────────
      // The edit icon in the Profile app bar (profile_screen.dart) pushes
      // /profile/edit. find.byIcon(...).first hits the app-bar button.
      if (await _tapIcon(tester, Icons.edit_outlined)) {
        await _settle(tester, seconds: 6);
        await capture('edit-profile');
        await _goBack(tester);
        await _settle(tester, seconds: 4);
      }

      // ── 12. Settings ─────────────────────────────────────────────────────
      if (await _tapIcon(tester, Icons.settings_outlined)) {
        await _settle(tester, seconds: 6);
        await capture('settings');
        await _goBack(tester);
        await _settle(tester, seconds: 4);
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

/// Taps the first widget whose text contains any of [substrings], trying each
/// in order. Used to open a list item (shift, etc.) without knowing the exact
/// demo data on the backend.
Future<bool> _tapFirstText(WidgetTester tester, List<String> substrings) async {
  for (final substring in substrings) {
    final finder = find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains(substring),
    );
    if (tester.any(finder)) {
      await tester.tap(finder.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      return true;
    }
  }
  debugPrint('WARNING: no text containing any of $substrings — skipping');
  return false;
}

/// Taps the first widget of type [T] on screen (e.g. a ListTile row or an
/// InkWell-wrapped card). Returns false, and captures nothing, when none exist.
Future<bool> _tapFirstOfType<T extends Widget>(WidgetTester tester) async {
  final finder = find.byType(T);
  if (!tester.any(finder)) {
    debugPrint('WARNING: no $T on screen — skipping');
    return false;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  return true;
}

/// Pops the current pushed route. Detail screens use a default AppBar, which
/// auto-inserts a BackButton when pushed; fall back to the platform back icons
/// if a custom app bar is in play.
Future<bool> _goBack(WidgetTester tester) async {
  final backButton = find.byType(BackButton);
  if (tester.any(backButton)) {
    await tester.tap(backButton.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    return true;
  }
  for (final icon in [
    Icons.arrow_back_ios_new,
    Icons.arrow_back_ios,
    Icons.arrow_back,
    Icons.close,
  ]) {
    final finder = find.byIcon(icon);
    if (tester.any(finder)) {
      await tester.tap(finder.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      return true;
    }
  }
  debugPrint('WARNING: no back affordance found — cannot pop');
  return false;
}
