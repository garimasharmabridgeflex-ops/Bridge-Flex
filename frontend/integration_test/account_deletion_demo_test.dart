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

    // Settle for initial load (Firebase init, Remote Config, Auth check)
    await _settle(tester, seconds: 12);

    debugPrint('STEP 1: Check initial screen is Sign-In');
    final signInTitle = find.text('Sign in');
    if (!tester.any(signInTitle)) {
      // If already signed in, log out first to cleanly demo sign in
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

    debugPrint('STEP 2: Enter Email & Password');
    final fields = find.byType(TextField);
    expect(fields, findsAtLeastNWidgets(2), reason: 'Sign-in fields must be visible');

    await tester.enterText(fields.at(0), _email);
    await tester.pump(const Duration(milliseconds: 600));

    await tester.enterText(fields.at(1), _password);
    await tester.pump(const Duration(milliseconds: 600));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 600));

    debugPrint('STEP 3: Tap Sign in');
    final signInBtn = find.widgetWithText(ElevatedButton, 'Sign in');
    if (tester.any(signInBtn)) {
      await tester.tap(signInBtn.first, warnIfMissed: false);
    } else {
      await tester.tap(find.text('Sign in').first, warnIfMissed: false);
    }

    // Wait for auth & profile loading, landing on the main shell
    await _settle(tester, seconds: 12);

    debugPrint('STEP 4: Navigate to Profile Tab');
    final profileIconFinder = find.byIcon(_profileIcon);
    expect(profileIconFinder, findsWidgets, reason: 'Profile navigation icon must be present');
    await tester.tap(profileIconFinder.first, warnIfMissed: false);
    await _settle(tester, seconds: 6);

    debugPrint('STEP 5: Scroll to and tap Delete Account');
    final deleteAccountTile = find.text('Delete Account');
    if (tester.any(deleteAccountTile)) {
      await tester.ensureVisible(deleteAccountTile);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(deleteAccountTile.first, warnIfMissed: false);
    } else {
      // Alternatively find via Settings
      final settingsIcon = find.byIcon(Icons.settings_outlined);
      if (tester.any(settingsIcon)) {
        await tester.tap(settingsIcon.first, warnIfMissed: false);
        await _settle(tester, seconds: 5);
        final settingsDelete = find.text('Delete account');
        await tester.ensureVisible(settingsDelete);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(settingsDelete.first, warnIfMissed: false);
      }
    }
    await _settle(tester, seconds: 4);

    debugPrint('STEP 6: Confirm Deletion in Dialog');
    final confirmDialogTitle = find.text('Delete your account?');
    expect(confirmDialogTitle, findsOneWidget, reason: 'Confirmation dialog must appear');

    // Tap "Delete account" in the confirmation dialog actions
    final confirmBtn = find.widgetWithText(TextButton, 'Delete account');
    expect(confirmBtn, findsOneWidget, reason: 'Delete account confirmation button must be visible');
    await tester.tap(confirmBtn, warnIfMissed: false);

    debugPrint('STEP 7: Wait for backend deletion and auto-redirect to /sign-in');
    // Backend erases profile, documents, FCM tokens, and deletes Firebase Auth user.
    // Auth state then goes null and router redirects to /sign-in.
    await _settle(tester, seconds: 12);

    // Verify we are back on Sign-in screen
    expect(find.byType(TextField), findsAtLeastNWidgets(2), reason: 'Must return to sign-in screen after account deletion');
    debugPrint('STEP 8: Account deletion completed successfully and returned to sign-in screen');

    // Pause briefly for the video recording to show the clean signed-out state
    await _settle(tester, seconds: 4);
  });
}

Future<void> _settle(WidgetTester tester, {required int seconds}) async {
  for (var i = 0; i < seconds * 2; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}
