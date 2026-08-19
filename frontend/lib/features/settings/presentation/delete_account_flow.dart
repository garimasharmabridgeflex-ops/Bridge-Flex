import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_exception.dart';

/// Confirms and then permanently deletes the signed-in user's account.
///
/// Lives here rather than inside a single screen because App Store Review
/// guideline 5.1.1(v) requires account deletion to be *findable*: the flow is
/// offered both on the Profile screen and under Settings, and both must
/// behave identically. Reviewers rejected build 21 for not finding it at all
/// when it was only reachable through an unlabelled gear icon.
///
/// Returns true if the account was deleted. The caller does not need to
/// navigate afterwards — the router redirects to /sign-in on its own once the
/// auth state goes null.
Future<bool> confirmAndDeleteAccount(BuildContext context, WidgetRef ref) async {
  final scheme = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.maybeOf(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete your account?'),
      content: const Text(
        'This permanently deletes your profile, your uploaded documents, your '
        'public listing and your login.\n\n'
        "It happens immediately and can't be undone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          child: const Text('Delete account'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final authRepo = ref.read(authRepositoryProvider);

  // Apple requires an app to revoke its Apple ID access when the user deletes
  // their account — deleting the Firebase user alone leaves KFlex listed under
  // the user's Apple ID forever. This re-opens Apple's sheet to mint a fresh
  // authorization code, so a dismissal here aborts the deletion rather than
  // leaving that half-done.
  if (authRepo.hasAppleProvider) {
    try {
      final revoked = await authRepo.revokeAppleToken();
      if (!revoked) return false;
    } on SignInWithAppleException {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't confirm with Apple — your account was not deleted."),
        ),
      );
      return false;
    }
  }

  try {
    await ref.read(profileRepositoryProvider).deleteAccount();
  } on ApiException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }

  await authRepo.signOut();
  return true;
}
