import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/constants/profile_options.dart';
import '../../../shared/widgets/chip_multi_select.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/status_badge.dart';
import '../domain/profile.dart';

class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(publicProfileProvider(uid));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(publicProfileProvider(uid));
        },
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const SizedBox(height: 80),
              EmptyState(icon: Icons.error_outline, title: "Couldn't load profile", subtitle: '$e'),
            ],
          ),
          data: (profile) {
            if (profile == null) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: const [
                  SizedBox(height: 80),
                  EmptyState(icon: Icons.person_off_outlined, title: 'Profile not found'),
                ],
              );
            }
            final isNursery = profile.role == UserRole.nursery;
            final avatarUrl = isNursery && profile.logoUrl.isNotEmpty ? profile.logoUrl : profile.photoUrl;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.w800, color: scheme.primary),
                            )
                          : null,
                    ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 12),
                    Text(profile.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      isNursery ? nurseryTypeLabelOrDefault(profile.nurseryType) : 'Staff',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (profile.locationArea.isNotEmpty || (isNursery && profile.city.isEmpty)) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.place_outlined, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(profile.locationArea,
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ],
                    if (!isNursery && profile.city.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_city_outlined, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            profile.travelDistanceMiles > 0
                                ? '${profile.city} · willing to travel ${profile.travelDistanceMiles}mi'
                                : profile.city,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isNursery) ...[
                          DbsBadge(status: profile.dbsBadge),
                          const SizedBox(width: 8),
                        ],
                        Container(
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
                                profile.rating.count == 0
                                    ? 'No ratings yet'
                                    : '${profile.rating.average.toStringAsFixed(1)} (${profile.rating.count})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: AppColors.amber),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: AppSpacing.xl),
              if (isNursery)
                _NurseryDetails(profile: profile)
              else
                _StaffDetails(profile: profile),
            ],
          );
        },
      ),
    ),
    );
  }
}

String nurseryTypeLabelOrDefault(NurseryType type) =>
    type == NurseryType.unspecified ? 'Nursery' : nurseryTypeLabel(type);

class _NurseryDetails extends StatelessWidget {
  const _NurseryDetails({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasContactInfo = profile.website.isNotEmpty ||
        profile.postcode.isNotEmpty ||
        profile.phone.isNotEmpty ||
        profile.email.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile.identityVerified || profile.ofstedVerified) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile.identityVerified)
                const Chip(
                  avatar: Icon(Icons.verified_rounded, color: AppColors.mint, size: 18),
                  label: Text('Identity Verified', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              if (profile.ofstedVerified)
                const Chip(
                  avatar: Icon(Icons.school_rounded, color: AppColors.indigo, size: 18),
                  label: Text('Ofsted Verified', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (profile.photos.isNotEmpty) ...[
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: profile.photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.network(profile.photos[i], width: 160, height: 120, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (profile.shortDescription.isNotEmpty) ...[
          Text(profile.shortDescription,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: AppSpacing.md),
        ],
        if (profile.description.isNotEmpty) ...[
          Text('About', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(profile.description),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (profile.registeredCompanyName.isNotEmpty)
          _InfoRow(icon: Icons.business_outlined, label: 'Registered company', value: profile.registeredCompanyName),
        if (profile.ofstedRegNumber.isNotEmpty)
          _InfoRow(icon: Icons.badge_outlined, label: 'Ofsted registration number', value: profile.ofstedRegNumber),
        if (profile.yearEstablished > 0)
          _InfoRow(icon: Icons.calendar_today_outlined, label: 'Established', value: '${profile.yearEstablished}'),
        if (profile.openingHours.isNotEmpty)
          _InfoRow(icon: Icons.schedule_outlined, label: 'Opening hours', value: profile.openingHours),
        if (profile.ofstedRating != OfstedRating.notRated)
          _InfoRow(
            icon: Icons.school_outlined,
            label: 'Ofsted rating',
            value: ofstedRatingLabel(profile.ofstedRating),
          ),
        if (profile.postcode.isNotEmpty)
          _InfoRow(icon: Icons.markunread_mailbox_outlined, label: 'Postcode', value: profile.postcode),
        if (profile.phone.isNotEmpty)
          _InfoRow(icon: Icons.call_outlined, label: 'Phone', value: profile.phone),
        if (profile.email.isNotEmpty)
          _InfoRow(icon: Icons.email_outlined, label: 'Email', value: profile.email),
        if (profile.website.isNotEmpty)
          _InfoRow(icon: Icons.language_outlined, label: 'Website', value: profile.website),
        if (profile.facilities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Facilities', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ChipDisplayRow(values: profile.facilities, options: nurseryFacilityOptions),
        ],
        if (profile.stats != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Statistics', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _StatsGrid(stats: profile.stats!),
        ],
        if (profile.description.isEmpty &&
            profile.openingHours.isEmpty &&
            profile.photos.isEmpty &&
            !hasContactInfo)
          Text(
            "This nursery hasn't filled out their profile yet.",
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final NurseryStats stats;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.event_available_outlined, 'Completed shifts', '${stats.completedShifts}'),
      (Icons.repeat_rounded, 'Repeat staff', '${stats.repeatStaffPercentage.toStringAsFixed(0)}%'),
      if (stats.averageResponseTimeMinutes > 0)
        (
          Icons.timer_outlined,
          'Avg. response time',
          stats.averageResponseTimeMinutes < 60
              ? '${stats.averageResponseTimeMinutes.round()}m'
              : '${(stats.averageResponseTimeMinutes / 60).toStringAsFixed(1)}h',
        ),
      (Icons.cancel_outlined, 'Cancellation rate', '${(stats.cancellationRate * 100).toStringAsFixed(0)}%'),
      (Icons.person_off_outlined, 'No-show rate', '${(stats.noShowRate * 100).toStringAsFixed(0)}%'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.$1, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(item.$3, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              Text(item.$2, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _StaffDetails extends StatelessWidget {
  const _StaffDetails({required this.profile});

  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAnything = profile.bio.isNotEmpty ||
        profile.professionalSummary.isNotEmpty ||
        profile.yearsExperience > 0 ||
        profile.qualificationLevel != QualificationLevel.none ||
        profile.previousRoles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (profile.professionalSummary.isNotEmpty) ...[
          Text(profile.professionalSummary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: AppSpacing.md),
        ],
        if (profile.bio.isNotEmpty) ...[
          Text('About', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(profile.bio),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (profile.age != null)
          _InfoRow(icon: Icons.cake_outlined, label: 'Age', value: '${profile.age}'),
        if (profile.yearsExperience > 0)
          _InfoRow(
            icon: Icons.work_history_outlined,
            label: 'Experience',
            value:
                '${profile.yearsExperience} ${profile.yearsExperience == 1 ? 'year' : 'years'}',
          ),
        if (profile.qualificationLevel != QualificationLevel.none)
          _InfoRow(
            icon: Icons.school_outlined,
            label: 'Qualification',
            value: qualificationLevelLabel(profile.qualificationLevel),
          ),
        if (profile.nationality.isNotEmpty)
          _InfoRow(icon: Icons.flag_outlined, label: 'Nationality', value: profile.nationality),
        if (profile.visaStatus.isNotEmpty)
          _InfoRow(
            icon: Icons.assignment_ind_outlined,
            label: 'Visa status',
            value: visaStatusLabel(profile.visaStatus),
          ),
        if (profile.rightToWorkStatus.isNotEmpty)
          _InfoRow(
            icon: Icons.how_to_reg_outlined,
            label: 'Right to work',
            value: rightToWorkStatusLabel(profile.rightToWorkStatus),
          ),
        if (profile.languages.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Languages spoken', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ChipDisplayRow(values: profile.languages, options: commonLanguageOptions),
        ],
        if (profile.skills.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Skills', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ChipDisplayRow(values: profile.skills, options: staffSkillOptions),
        ],
        if (profile.qualifications.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Qualifications', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ChipDisplayRow(values: profile.qualifications, options: staffQualificationOptions),
        ],
        if (profile.availabilityDays.isNotEmpty || profile.availabilityShifts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Availability', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          if (profile.availabilityDays.isNotEmpty)
            ChipDisplayRow(values: profile.availabilityDays, options: availabilityDayOptions),
          if (profile.availabilityShifts.isNotEmpty) ...[
            const SizedBox(height: 8),
            ChipDisplayRow(values: profile.availabilityShifts, options: availabilityShiftOptions),
          ],
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Verified Badges & Credentials', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (profile.dbsBadge == DbsStatus.verified)
              Chip(
                avatar: const Icon(Icons.verified_user_rounded, color: AppColors.mint, size: 18),
                label: Text(
                  profile.dbsExpiryDate != null
                      ? 'DBS Verified by Bridge Flex · expires ${profile.dbsExpiryDate!.day}/${profile.dbsExpiryDate!.month}/${profile.dbsExpiryDate!.year}'
                      : 'DBS Verified by Bridge Flex',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            else if (profile.dbsBadge == DbsStatus.pending)
              const Chip(
                avatar: Icon(Icons.hourglass_top_rounded, color: AppColors.amber, size: 18),
                label: Text('DBS Review Pending', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (profile.qualificationLevel != QualificationLevel.none)
              Chip(
                avatar: const Icon(Icons.card_membership_rounded, color: AppColors.indigo, size: 18),
                label: Text('${qualificationLevelLabel(profile.qualificationLevel)} Certified', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (profile.rightToWorkVerified)
              const Chip(
                avatar: Icon(Icons.how_to_reg_rounded, color: AppColors.coral, size: 18),
                label: Text('Right to Work Verified', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        if (profile.ratingBreakdown != null && profile.ratingBreakdown!.hasData) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Ratings breakdown', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _RatingBreakdownRows(breakdown: profile.ratingBreakdown!),
        ],
        if (profile.previousRoles.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Previous roles', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          ...profile.previousRoles.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${r.roleTitle} · ${r.settingName}${r.duration.isNotEmpty ? ' (${r.duration})' : ''}',
                      ),
                    ),
                  ],
                ),
              )),
        ],
        if (!hasAnything)
          Text(
            "This staff member hasn't added experience details yet.",
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _RatingBreakdownRows extends StatelessWidget {
  const _RatingBreakdownRows({required this.breakdown});
  final RatingBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Communication', breakdown.communication),
      ('Punctuality', breakdown.punctuality),
      ('Professionalism', breakdown.professionalism),
      ('Reliability', breakdown.reliability),
      ('Child engagement', breakdown.childEngagement),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: rows.map((r) {
        final (label, value) = r;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (value / 5).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: AppColors.amber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 28, child: Text(value.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
