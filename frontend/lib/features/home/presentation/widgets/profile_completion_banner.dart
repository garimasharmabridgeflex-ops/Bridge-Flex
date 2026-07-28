import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../profile/domain/profile.dart';

/// Full app spec §1.4: "A partially-complete profile ... is allowed into
/// the app, but with a persistent, dismissible-but-reappearing banner."
/// Dismissal is intentionally not persisted — it comes back next time the
/// shell rebuilds (app relaunch, tab switch away and back), which is what
/// "reappearing" means here, rather than a one-and-done dismiss.
class ProfileCompletionBanner extends StatelessWidget {
  const ProfileCompletionBanner({super.key, required this.profile, required this.onDismiss});

  final Profile profile;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isStaff = profile.role == UserRole.staff;
    final message = isStaff
        ? "Finish your profile to start accepting shifts — add DBS verification and a bit about your experience."
        : "Add a description so staff know what to expect before they accept your shifts.";

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => context.push('/profile/edit'),
                  child: Text(
                    'Finish now →',
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
            onPressed: onDismiss,
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
