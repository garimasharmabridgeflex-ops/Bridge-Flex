import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme.dart';

/// Firebase caches `emailVerified` on the local [User] object from sign-in
/// time — reload() re-fetches it from Auth so a just-clicked verification
/// link is reflected without the user having to sign out and back in.
/// A Google sign-in always comes back verified, so this naturally never
/// shows for those accounts.
final emailVerifiedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final authRepo = ref.watch(authRepositoryProvider);
  await authRepo.reloadUser();
  return authRepo.currentUser?.emailVerified ?? true;
});

/// Full app spec gap: the sign-up verification email was sent but nothing
/// in the app ever checked whether it was actually opened — this closes
/// that loop with a resend action, mirroring [ProfileCompletionBanner]'s
/// "dismissible-but-reappearing" style (session-only dismissal).
class EmailVerificationBanner extends ConsumerStatefulWidget {
  const EmailVerificationBanner({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  ConsumerState<EmailVerificationBanner> createState() => _EmailVerificationBannerState();
}

class _EmailVerificationBannerState extends ConsumerState<EmailVerificationBanner> {
  bool _sending = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Verification email sent.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Couldn't send the email — try again shortly.")));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: AppColors.coral, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please verify your email address.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _sending ? null : _resend,
                  child: Text(
                    _sending ? 'Sending…' : 'Resend email →',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
  }
}
