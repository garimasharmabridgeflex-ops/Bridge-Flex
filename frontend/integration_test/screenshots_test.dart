// Drives the app through every screen a signed-in STAFF member and a signed-in
// NURSERY can reach, capturing a screenshot of each at the simulator's native
// resolution — so App Store screenshots for both sides of the marketplace can
// be produced in CI without owning the device.
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
// Signs in with the seeded demo accounts (backend/seed/demo) so screens have
// real content rather than empty states. It runs the staff flow first, taps
// Logout, then signs in as the nursery and runs the nursery flow — the nursery
// tabs also exercise the floating nav bar's center "Post shift" FAB layout.
//
// Every step is individually guarded: a selector that fails to match logs a
// warning and moves on rather than aborting the run, so one changed label or a
// missing bit of demo data still yields a usable set of screenshots.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bridgeflex_app/main.dart' as app;

// All seeded demo accounts share one password (backend/seed/demo/main.go).
const _password = 'BridgeFlexDemo2026!';
const _staffEmail = 'afrilexkenya+demo.staff@gmail.com';
const _nurseryEmail = 'afrilexkenya+demo.nursery@gmail.com';

// Bottom-nav tabs are tapped by ICON, not label: floating_nav_bar.dart only
// renders the label for the currently selected tab, so find.text('Messages')
// never matches while another tab is active. Icons are the unselected variants
// from home_shell.dart.
const _browseIcon = Icons.search_outlined;
const _myShiftsIcon = Icons.event_note_outlined;
const _messagesIcon = Icons.chat_bubble_outline_rounded;
const _trainingIcon = Icons.school_outlined;
const _profileIcon = Icons.person_outline_rounded;

late IntegrationTestWidgetsFlutterBinding _binding;
var _shot = 0;

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture App Store screenshots', (tester) async {
    app.main();

    // Firebase init, Remote Config fetch and the auth state check all happen
    // on first frame; pumpAndSettle alone races them.
    await _settle(tester, seconds: 12);

    // ── Shared: the sign-in screen ─────────────────────────────────────────
    await _capture('sign-in');

    // ── STAFF ──────────────────────────────────────────────────────────────
    await _signIn(tester, _staffEmail);
    await _staffFlow(tester);

    // ── Switch to the nursery account ──────────────────────────────────────
    // Logout is a plain button on the Profile screen that calls signOut()
    // directly (no dialog); auth state then flips go_router back to sign-in.
    if (await _logout(tester)) {
      await _settle(tester, seconds: 10);
      await _signIn(tester, _nurseryEmail);
      await _nurseryFlow(tester);
    }

    debugPrint('SCREENSHOTS done: $_shot captured');
  });
}

Future<void> _staffFlow(WidgetTester tester) async {
  // Browse (staff landing tab)
  await _tapIcon(tester, _browseIcon);
  await _settle(tester, seconds: 6);
  await _capture('staff-browse');

  // Shift detail
  if (await _tapFirstText(
    tester,
    ['Morning cover', 'Full day', 'Afternoon cover', 'cover', 'shift'],
  )) {
    await _settle(tester, seconds: 8);
    await _capture('staff-shift-detail');
    await _goBack(tester);
    await _settle(tester, seconds: 4);
  }

  // My shifts
  if (await _tapIcon(tester, _myShiftsIcon)) {
    await _settle(tester, seconds: 6);
    await _capture('staff-my-shifts');
  }

  // Notifications (bell lives in the Browse/My-shifts app bar)
  if (await _tapIcon(tester, Icons.notifications_outlined)) {
    await _settle(tester, seconds: 6);
    await _capture('staff-notifications');
    await _goBack(tester);
    await _settle(tester, seconds: 4);
  }

  // Messages + a chat
  if (await _tapIcon(tester, _messagesIcon)) {
    await _settle(tester, seconds: 6);
    await _capture('staff-messages');
    if (await _tapFirstOfType<ListTile>(tester)) {
      await _settle(tester, seconds: 6);
      await _capture('staff-chat');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }
  }

  // Training + a module
  if (await _tapIcon(tester, _trainingIcon)) {
    await _settle(tester, seconds: 6);
    await _capture('staff-training');
    if (await _tapFirstOfType<InkWell>(tester)) {
      await _settle(tester, seconds: 6);
      await _capture('staff-training-module');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }
  }

  // Profile → settings → edit profile
  if (await _tapIcon(tester, _profileIcon)) {
    await _settle(tester, seconds: 6);
    await _capture('staff-profile');

    if (await _tapIcon(tester, Icons.settings_outlined)) {
      await _settle(tester, seconds: 6);
      await _capture('staff-settings');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }

    // Edit profile is a form full of EditableTexts — see _captureForm for why
    // it needs the error guard. Pop afterwards so we're back on Profile to log
    // out for the nursery pass.
    await _captureForm(tester, 'staff-edit-profile', Icons.edit_outlined);
    await _goBackGuarded(tester);
    await _settle(tester, seconds: 4);
  }
}

Future<void> _nurseryFlow(WidgetTester tester) async {
  // Shifts (a nursery's landing tab — no Browse tab for nurseries)
  await _tapIcon(tester, _myShiftsIcon);
  await _settle(tester, seconds: 6);
  await _capture('nursery-shifts');

  // A posted shift's detail
  if (await _tapFirstText(
    tester,
    ['Morning cover', 'Full day', 'Afternoon cover', 'cover', 'shift'],
  )) {
    await _settle(tester, seconds: 8);
    await _capture('nursery-shift-detail');
    await _goBack(tester);
    await _settle(tester, seconds: 4);
  }

  // Notifications
  if (await _tapIcon(tester, Icons.notifications_outlined)) {
    await _settle(tester, seconds: 6);
    await _capture('nursery-notifications');
    await _goBack(tester);
    await _settle(tester, seconds: 4);
  }

  // Post a shift — the center FAB (Icons.add_rounded straddling the nav bar).
  // /shifts/new is a form, so capture it with the error guard.
  await _captureForm(tester, 'nursery-post-shift', Icons.add_rounded);
  await _goBackGuarded(tester);
  await _settle(tester, seconds: 4);

  // Messages + a chat
  if (await _tapIcon(tester, _messagesIcon)) {
    await _settle(tester, seconds: 6);
    await _capture('nursery-messages');
    if (await _tapFirstOfType<ListTile>(tester)) {
      await _settle(tester, seconds: 6);
      await _capture('nursery-chat');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }
  }

  // Profile — this screen (and every nursery tab) shows the floating nav bar
  // with the centered Post-shift FAB, i.e. the layout being verified.
  if (await _tapIcon(tester, _profileIcon)) {
    await _settle(tester, seconds: 6);
    await _capture('nursery-profile');

    if (await _tapIcon(tester, Icons.settings_outlined)) {
      await _settle(tester, seconds: 6);
      await _capture('nursery-settings');
      await _goBack(tester);
      await _settle(tester, seconds: 4);
    }
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

Future<void> _capture(String name) async {
  _shot++;
  final label = '${_shot.toString().padLeft(2, '0')}-$name';
  await _binding.takeScreenshot(label);
  debugPrint('SCREENSHOT captured: $label');
}

/// Opens a form screen via [openIcon] and captures it. Form screens are full of
/// EditableTexts, and in the integration_test harness a field rebuilding during
/// the push transition can trip the framework assert "Tried to build dirty
/// widget in the wrong build scope". It does not corrupt the captured PNG, but
/// integration_test fails the whole run on any unexpected exception (and the
/// broken frame can also hide the AppBar BackButton). So: unfocus so no field
/// is live during the transition, and swallow framework errors for just this
/// step, draining any the harness already queued, so the run still exits green.
Future<void> _captureForm(
  WidgetTester tester,
  String name,
  IconData openIcon,
) async {
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint('IGNORED during $name: ${details.exceptionAsString()}');
  };
  try {
    if (await _tapIcon(tester, openIcon)) {
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester, seconds: 6);
      await _capture(name);
    }
  } finally {
    while (tester.takeException() != null) {}
    FlutterError.onError = priorOnError;
  }
}

/// Enters credentials on the sign-in screen and submits. No-op with a warning
/// if the sign-in fields aren't present (e.g. still signed in).
Future<void> _signIn(WidgetTester tester, String email) async {
  final fields = find.byType(TextField);
  if (tester.any(fields) && fields.evaluate().length >= 2) {
    await tester.enterText(fields.at(0), email);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(fields.at(1), _password);
    await tester.pump(const Duration(milliseconds: 300));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await _tapText(tester, 'Sign in');
    await _settle(tester, seconds: 15);
  } else {
    debugPrint('WARNING: sign-in fields not found for $email — already signed in?');
  }
}

/// Goes to the Profile tab and taps the Logout button (scrolled into view).
Future<bool> _logout(WidgetTester tester) async {
  await _tapIcon(tester, _profileIcon);
  await _settle(tester, seconds: 5);
  final logout = find.text('Logout');
  if (!tester.any(logout)) {
    debugPrint('WARNING: Logout button not found — cannot switch accounts');
    return false;
  }
  await tester.ensureVisible(logout);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(logout, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
  return true;
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

/// _goBack, but with the same framework-error guard _captureForm uses — popping
/// a form screen can throw the same EditableText build-scope assert.
Future<bool> _goBackGuarded(WidgetTester tester) async {
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint('IGNORED during back: ${details.exceptionAsString()}');
  };
  try {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    return await _goBack(tester);
  } finally {
    while (tester.takeException() != null) {}
    FlutterError.onError = priorOnError;
  }
}
