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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isStaff
                  ? "Finish your profile (DBS & bio) to start taking shifts."
                  : "Add your nursery description so staff know your setting.",
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF92400E)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => context.push('/profile/edit'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Complete', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFFB45309))),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: Color(0xFFB45309)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
  }
}
