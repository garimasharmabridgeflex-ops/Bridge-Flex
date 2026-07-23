import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/status_badge.dart';
import '../domain/profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(ownProfileProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      backgroundImage:
                          profile.photoUrl.isNotEmpty ? NetworkImage(profile.photoUrl) : null,
                      child: profile.photoUrl.isEmpty
                          ? Text(
                              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            )
                          : null,
                    ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 12),
                    Text(
                      profile.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.role == UserRole.nursery ? 'Nursery' : 'Staff',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (profile.role == UserRole.staff) ...[
                          DbsBadge(status: profile.dbsStatus),
                          const SizedBox(width: 8),
                        ],
                        _RatingChip(rating: profile.rating.average, count: profile.rating.count),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: AppSpacing.lg),
              if (profile.role == UserRole.nursery && profile.stats != null)
                _StatRow(
                  items: [
                    _StatItem(Icons.event_available_rounded, '${profile.stats!.completedShifts}', 'Shifts done'),
                    _StatItem(Icons.repeat_rounded, '${profile.stats!.repeatStaffPercentage.round()}%', 'Repeat staff'),
                    _StatItem(Icons.bolt_rounded, '${profile.stats!.averageResponseTimeMinutes.round()}m', 'Avg response'),
                  ],
                ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
              if (profile.role == UserRole.staff)
                _StatRow(
                  items: [
                    _StatItem(Icons.work_history_rounded, '${profile.yearsExperience}', 'Years exp.'),
                    _StatItem(Icons.school_rounded, qualificationLevelLabel(profile.qualificationLevel), 'Level'),
                    _StatItem(
                      Icons.star_rounded,
                      profile.rating.count == 0 ? '—' : profile.rating.average.toStringAsFixed(1),
                      'Rating',
                    ),
                  ],
                ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
              const SizedBox(height: AppSpacing.xl),
              if (profile.role == UserRole.nursery && profile.description.isNotEmpty) ...[
                Text('About', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(profile.description),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (profile.role == UserRole.staff && profile.bio.isNotEmpty) ...[
                Text('About', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(profile.bio),
                const SizedBox(height: AppSpacing.lg),
              ],
              _ActionTile(
                icon: Icons.edit_outlined,
                label: 'Edit profile',
                onTap: () => context.push('/profile/edit'),
              ),
              if (profile.role == UserRole.staff)
                _ActionTile(
                  icon: Icons.upload_file_outlined,
                  label: 'Upload DBS certificate',
                  onTap: () => context.push('/profile/dbs'),
                ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: () => ref.read(authRepositoryProvider).signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating, required this.count});

  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
          const SizedBox(width: 4),
          Text(
            count == 0 ? 'No ratings yet' : '${rating.toStringAsFixed(1)} ($count)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.amber),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
}

/// The "job done / points / reviews" stat-pill row pattern — a snapshot of
/// the profile's key numbers at a glance, above the detail sections.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.items});
  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 20, color: AppColors.mint),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
