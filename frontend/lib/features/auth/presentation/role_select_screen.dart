import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../onboarding/presentation/widgets/onboarding_illustration.dart';
import '../../profile/domain/profile.dart';

class RoleSelectScreen extends ConsumerStatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  ConsumerState<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends ConsumerState<RoleSelectScreen> {
  bool _loading = false;

  Future<void> _choose(UserRole role) async {
    setState(() => _loading = true);
    try {
      await ref.read(profileRepositoryProvider).setRole(role);
      // ownProfileProvider is a one-shot fetch now (see providers.dart) —
      // invalidate to refetch, which is what triggers the router redirect.
      ref.invalidate(ownProfileProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: const OnboardingIllustration(
                  icon: Icons.diversity_3_rounded,
                  color: AppColors.indigo,
                  satellites: [Icons.home_work_rounded, Icons.badge_rounded],
                  size: 132,
                ).animate().fadeIn(duration: 350.ms),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                "How will you use\nBridge Flex?",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
              ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 8),
              Text(
                'This decides what you can post and book. It only gets set once.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ).animate().fadeIn(delay: 80.ms, duration: 350.ms),
              const SizedBox(height: AppSpacing.xl),
              _RoleCard(
                icon: Icons.home_work_outlined,
                title: "I'm a nursery",
                subtitle: 'Post last-minute shifts and book qualified staff.',
                color: AppColors.indigo,
                loading: _loading,
                onTap: () => _choose(UserRole.nursery),
              ).animate().fadeIn(delay: 150.ms, duration: 350.ms).slideX(begin: -0.05, end: 0),
              const SizedBox(height: AppSpacing.md),
              _RoleCard(
                icon: Icons.badge_outlined,
                title: "I'm staff",
                subtitle: 'Browse open shifts nearby and get booked fast.',
                color: AppColors.coral,
                loading: _loading,
                onTap: () => _choose(UserRole.staff),
              ).animate().fadeIn(delay: 220.ms, duration: 350.ms).slideX(begin: 0.05, end: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.loading,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
