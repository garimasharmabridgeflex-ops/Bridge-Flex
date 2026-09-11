import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bridgeflex_app/main.dart' as app;

// Credentials for deletion demo.
// Configurable via --dart-define=DEMO_EMAIL=... and --dart-define=DEMO_PASSWORD=...
// Defaults to the seeded staff demo user.
const _defaultEmail = 'afrilexkenya+demo.staff@gmail.com';
const _defaultPassword = 'BridgeFlexDemo2026!';

const _email = String.fromEnvironment('DEMO_EMAIL', defaultValue: _defaultEmail);
const _password = String.fromEnvironment('DEMO_PASSWORD', defaultValue: _defaultPassword);

const _profileIcon = Icons.person_outline_rounded;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo sign in and account deletion', (tester) async {
    app.main();

    // Generous settle for initial load (Firebase init, Remote Config, Auth)
    await _settle(tester, seconds: 15);

    // ---- STEP 1: Ensure we are on the Sign-In screen ----
    debugPrint('STEP 1: Check initial screen is Sign-In');
    final signInTitle = find.text('Sign in');
    if (!tester.any(signInTitle)) {
      debugPrint('  → Not on sign-in screen, attempting logout first');
      final profileTab = find.byIcon(_profileIcon);
      if (tester.any(profileTab)) {
        await tester.tap(profileTab.first, warnIfMissed: false);
        await _settle(tester, seconds: 5);
        final logoutBtn = find.text('Logout');
        if (tester.any(logoutBtn)) {
          await tester.ensureVisible(logoutBtn);
          await tester.tap(logoutBtn, warnIfMissed: false);
          await _settle(tester, seconds: 8);
        }
      }
    }

    // ---- STEP 2: Enter Credentials ----
    debugPrint('STEP 2: Enter Email & Password');
    final fields = find.byType(TextField);
    if (tester.widgetList(fields).length < 2) {
      debugPrint('  ⚠ WARN: Could not find email/password fields');
      await _settle(tester, seconds: 5);
    }

    await tester.enterText(fields.at(0), _email);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.enterText(fields.at(1), _password);
    await tester.pump(const Duration(milliseconds: 600));

    // Dismiss keyboard
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));

    // ---- STEP 3: Tap Sign In ----
    debugPrint('STEP 3: Tap Sign in');
    final signInBtn = find.widgetWithText(ElevatedButton, 'Sign in');
    if (tester.any(signInBtn)) {
      await tester.tap(signInBtn.first, warnIfMissed: false);
    } else {
      final signInText = find.text('Sign in');
      if (tester.any(signInText)) {
        await tester.tap(signInText.first, warnIfMissed: false);
      } else {
        debugPrint('  ⚠ WARN: Could not find Sign in button');
      }
    }

    // Wait for auth + profile loading + landing on main shell.
    // Notification permission is pre-granted in CI so no native dialog appears.
    await _settle(tester, seconds: 15);

    // ---- STEP 4: Navigate to Profile Tab ----
    debugPrint('STEP 4: Navigate to Profile Tab');
    // NOTE: person_outline_rounded icon appears in shift cards too.
    // The FloatingNavBar is at the BOTTOM of the widget tree, so use .last
    // to tap the nav bar icon, not a shift card icon near the top.
    final profileIconFinder = find.byIcon(_profileIcon);
    if (tester.any(profileIconFinder)) {
      await tester.tap(profileIconFinder.last, warnIfMissed: false);
      await _settle(tester, seconds: 6);
    } else {
      debugPrint('  ⚠ WARN: Profile icon not found anywhere');
      await _settle(tester, seconds: 6);
    }

    // ---- STEP 5: Scroll to and tap Delete Account ----
    debugPrint('STEP 5: Scroll to and tap Delete Account');
    bool deleteTapped = false;

    // Try "Delete Account" (ProfileScreen capital A)
    final deleteAccountTile = find.text('Delete Account');
    if (tester.any(deleteAccountTile)) {
      await tester.ensureVisible(deleteAccountTile.first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(deleteAccountTile.first, warnIfMissed: false);
      deleteTapped = true;
    }

    // Fallback: try via Settings screen
    if (!deleteTapped) {
      debugPrint('  → "Delete Account" not found, trying Settings...');
      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (tester.any(settingsIcon)) {
        await tester.tap(settingsIcon.first, warnIfMissed: false);
        await _settle(tester, seconds: 5);
        final settingsDelete = find.text('Delete account');
        if (tester.any(settingsDelete)) {
          await tester.ensureVisible(settingsDelete.first);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(settingsDelete.first, warnIfMissed: false);
          deleteTapped = true;
        }
      }
    }

    // Fallback: try by icon
    if (!deleteTapped) {
      debugPrint('  → Trying delete icon fallback...');
      final deleteIcon = find.byIcon(Icons.delete_forever_rounded);
      if (tester.any(deleteIcon)) {
        await tester.ensureVisible(deleteIcon.first);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(deleteIcon.first, warnIfMissed: false);
        deleteTapped = true;
      }
    }

    if (!deleteTapped) {
      debugPrint('  ⚠ WARN: Could not find Delete Account anywhere!');
    }
    await _settle(tester, seconds: 4);

    // ---- STEP 6: Confirm Deletion in Dialog ----
    debugPrint('STEP 6: Confirm Deletion in Dialog');
    final confirmDialogTitle = find.text('Delete your account?');
    if (tester.any(confirmDialogTitle)) {
      debugPrint('  → Confirmation dialog found');
      final confirmBtn = find.widgetWithText(TextButton, 'Delete account');
      if (tester.any(confirmBtn)) {
        await tester.tap(confirmBtn.first, warnIfMissed: false);
        debugPrint('  → Delete account confirmed');
      } else {
        debugPrint('  ⚠ WARN: Confirm button not found in dialog');
      }
    } else {
      debugPrint('  ⚠ WARN: Confirmation dialog did not appear');
    }

    // ---- STEP 7: Wait for deletion & redirect ----
    debugPrint('STEP 7: Wait for backend deletion and auto-redirect to /sign-in');
    await _settle(tester, seconds: 15);

    // Verify we are back on Sign-in screen
    final signInFields = find.byType(TextField);
    if (tester.widgetList(signInFields).length >= 2) {
      debugPrint('STEP 8: ✅ Account deletion completed — returned to sign-in screen');
    } else {
      debugPrint('STEP 8: ⚠ WARN: May not have returned to sign-in screen');
    }

    // Pause for the video recording to show the clean signed-out state
    await _settle(tester, seconds: 5);
  });
}

Future<void> _settle(WidgetTester tester, {required int seconds}) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}
