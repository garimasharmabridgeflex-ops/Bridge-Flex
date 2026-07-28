import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/services/uk_geocoding.dart';
import '../../../shared/widgets/status_badge.dart';
import '../domain/profile.dart';
import 'public_profile_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(ownProfileProvider);
    final scheme = Theme.of(context).colorScheme;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            onPressed: () => context.push('/profile/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (profile) {
          if (profile == null) return const SizedBox.shrink();
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // ── Cover banner + overlapping avatar ─────────────────────
              Container(
                padding: const EdgeInsets.only(bottom: 24, top: AppSpacing.lg),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.indigo, AppColors.indigoDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(AppRadius.lg),
                  ),
                ),
                child: Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 38,
                          backgroundColor: scheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          backgroundImage: profile.photoUrl.isNotEmpty
                              ? NetworkImage(profile.photoUrl)
                              : null,
                          child: profile.photoUrl.isEmpty
                              ? Text(
                                  profile.name.isNotEmpty
                                      ? profile.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                                )
                              : null,
                        ),
                      ).animate().scale(
                        duration: 300.ms,
                        curve: Curves.easeOutBack,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.role == UserRole.nursery ? 'Nursery' : 'Staff',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (profile.lat != null && profile.lng != null) ...[
                        const SizedBox(height: 2),
                        _OwnLocationRow(
                          lat: profile.lat!,
                          lng: profile.lng!,
                          light: true,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (profile.role == UserRole.staff) ...[
                            DbsBadge(status: profile.dbsStatus),
                            const SizedBox(width: 8),
                          ],
                          _RatingChip(
                            rating: profile.rating.average,
                            count: profile.rating.count,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (profile.role == UserRole.nursery &&
                        profile.stats != null)
                      _StatRow(
                        items: [
                          _StatItem(
                            Icons.work_outline_rounded,
                            '${profile.stats!.completedShifts}',
                            'Shifts done',
                          ),
                          _StatItem(
                            Icons.repeat_rounded,
                            '${profile.stats!.repeatStaffPercentage.round()}%',
                            'Repeat staff',
                          ),
                          _StatItem(
                            Icons.bolt_rounded,
                            '${profile.stats!.averageResponseTimeMinutes.round()}m',
                            'Avg response',
                          ),
                        ],
                      ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
                    if (profile.role == UserRole.staff)
                      _StatRow(
                        items: [
                          _StatItem(
                            Icons.work_history_rounded,
                            '${profile.yearsExperience} yrs',
                            'Years exp.',
                          ),
                          _StatItem(
                            Icons.school_rounded,
                            qualificationLevelLabel(profile.qualificationLevel),
                            'Qualification',
                          ),
                          _StatItem(
                            Icons.star_rounded,
                            profile.rating.count == 0
                                ? '—'
                                : '${profile.rating.average.toStringAsFixed(1)} ★',
                            'Rating (${profile.rating.count})',
                          ),
                        ],
                      ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
                    const SizedBox(height: AppSpacing.lg),
                    // Quick Design Menu Items (matching Job Finder Profile design)
                    _ActionTile(
                      icon: Icons.edit_outlined,
                      label: 'Edit Profile Information',
                      onTap: () => context.push('/profile/edit'),
                    ),
                    if (profile.role == UserRole.staff)
                      _ActionTile(
                        icon: Icons.description_outlined,
                        label: 'DBS Certificate & Compliance',
                        onTap: () => context.push('/profile/dbs'),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    if (profile.role == UserRole.nursery)
                      NurseryDetails(profile: profile.toPublicView(uid))
                    else
                      StaffDetails(profile: profile.toPublicView(uid)),
                    const SizedBox(height: AppSpacing.lg),
                    ReviewsList(uid: uid),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            ref.read(authRepositoryProvider).signOut(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF0ED),
                          foregroundColor: AppColors.coral,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                        child: const Text(
                          'Logout',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.coral,
                          ),
                        ),
                      ),
                    ),
                  ],
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
            count == 0
                ? 'No ratings yet'
                : '${rating.toStringAsFixed(1)} ($count)',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.amber,
            ),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
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
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: scheme.primary, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  height: 24,
                  width: 24,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: scheme.primary,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// GPS-detected coordinates otherwise had no visible representation
/// anywhere in the app — reverse-geocodes them (via postcodes.io) into a
/// readable place name for the profile header.
class _OwnLocationRow extends ConsumerWidget {
  const _OwnLocationRow({
    required this.lat,
    required this.lng,
    this.light = false,
  });
  final double lat;
  final double lng;
  final bool light;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = light
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final placeAsync = ref.watch(reverseGeocodeProvider((lat, lng)));
    final place = placeAsync.valueOrNull;
    if (place == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.place_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(place, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}
