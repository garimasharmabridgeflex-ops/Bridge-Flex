import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../profile/domain/profile.dart';
import '../../data/bookmarks_provider.dart';
import '../../domain/shift.dart';

const List<String> kDefaultNurseryPhotos = [
  'https://images.unsplash.com/photo-1576495199011-eb94736d05d6?auto=format&fit=crop&w=800&q=80',
  'https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=800&q=80',
  'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=800&q=80',
  'https://images.unsplash.com/photo-1544717305-2782549b5136?auto=format&fit=crop&w=800&q=80',
];

class ShiftCard extends ConsumerWidget {
  const ShiftCard({
    super.key,
    required this.shift,
    required this.onTap,
    this.trailingLabel,
    this.isPendingApproval = false,
  });

  final Shift shift;
  final VoidCallback onTap;
  final String? trailingLabel;
  final bool isPendingApproval;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBookmarked = ref.watch(bookmarkedShiftIdsProvider).contains(shift.id);
    final authUser = ref.watch(authStateProvider).valueOrNull;
    final myUid = authUser?.uid ?? '';
    final ownProfile = ref.watch(ownProfileProvider).valueOrNull;
    final isOwner = myUid.isNotEmpty && myUid == shift.nurseryId;
    final isNursery = ownProfile?.role == UserRole.nursery;
    final isStaff = ownProfile?.role == UserRole.staff;

    final nurseryProfile = isOwner
        ? null
        : ref.watch(publicProfileProvider(shift.nurseryId)).valueOrNull;

    // Use authentic nursery photo if available, with robust fallback
    String? authenticPhotoUrl;
    if (isOwner && ownProfile != null) {
      if (ownProfile.photos.isNotEmpty) {
        authenticPhotoUrl = ownProfile.photos.first;
      } else if (ownProfile.photoUrl.isNotEmpty) {
        authenticPhotoUrl = ownProfile.photoUrl;
      } else if (ownProfile.logoUrl.isNotEmpty) {
        authenticPhotoUrl = ownProfile.logoUrl;
      }
    } else if (nurseryProfile != null) {
      if (nurseryProfile.photos.isNotEmpty) {
        authenticPhotoUrl = nurseryProfile.photos.first;
      } else if (nurseryProfile.photoUrl.isNotEmpty) {
        authenticPhotoUrl = nurseryProfile.photoUrl;
      } else if (nurseryProfile.logoUrl.isNotEmpty) {
        authenticPhotoUrl = nurseryProfile.logoUrl;
      }
    }

    final photoUrl = authenticPhotoUrl ??
        kDefaultNurseryPhotos[shift.id.hashCode.abs() % kDefaultNurseryPhotos.length];

    final startFmt = DateFormat('HH:mm').format(shift.startTime);
    final endFmt = DateFormat('HH:mm').format(shift.endTime);

    final totalMinutes = shift.duration.inMinutes;
    final payableMinutes = (totalMinutes - shift.unpaidBreakMinutes).clamp(0, totalMinutes);
    final hoursFormatted = payableMinutes % 60 == 0
        ? '${payableMinutes ~/ 60}h'
        : '${(payableMinutes / 60.0).toStringAsFixed(1)}h';
    final breakFormatted = shift.unpaidBreakMinutes <= 0
        ? 'No break'
        : (shift.unpaidBreakMinutes % 60 == 0
            ? '${shift.unpaidBreakMinutes ~/ 60}h break'
            : '${shift.unpaidBreakMinutes}m break');

    final displayTitle = shift.title.isNotEmpty ? shift.title : 'Early Years Practitioner Cover';
    final String? ownerArea = (ownProfile?.city.isNotEmpty == true)
        ? ownProfile?.city
        : (ownProfile?.postcode.isNotEmpty == true ? ownProfile?.postcode : null);
    final rawArea = (shift.nurseryArea?.isNotEmpty ?? false)
        ? shift.nurseryArea!
        : (isOwner ? ownerArea : nurseryProfile?.locationArea)?.isNotEmpty == true
            ? (isOwner ? ownerArea! : nurseryProfile!.locationArea)
            : 'Early Years Setting';
    final settingName = (shift.nurseryName?.isNotEmpty ?? false)
        ? shift.nurseryName!
        : (isOwner ? ownProfile?.name : nurseryProfile?.name) ?? '';
    final branchText = shift.branchName.trim().isNotEmpty ? ' • ${shift.branchName.trim()}' : '';
    final settingDisplay = settingName.isNotEmpty ? '$settingName$branchText' : (shift.branchName.isNotEmpty ? shift.branchName : '');
    final nurseryArea = settingDisplay.isNotEmpty && rawArea != 'Early Years Setting' && !rawArea.contains(settingName)
        ? '$settingDisplay • $rawArea'
        : (settingDisplay.isNotEmpty ? settingDisplay : rawArea);

    // Role-aware context action label (replaces misleading "Book Shift")
    String defaultActionLabel;
    if (isOwner || isNursery) {
      if (shift.pendingStaffIds.isNotEmpty) {
        defaultActionLabel = 'Review (${shift.pendingStaffIds.length})';
      } else if (shift.status == ShiftStatus.open) {
        defaultActionLabel = 'Manage Shift';
      } else {
        defaultActionLabel = 'View Shift';
      }
    } else if (isStaff) {
      if (shift.bookedStaffIds.contains(myUid) || shift.bookedStaffId == myUid) {
        defaultActionLabel = 'Booked';
      } else if (shift.pendingStaffIds.contains(myUid)) {
        defaultActionLabel = 'Applied';
      } else if (shift.status == ShiftStatus.open) {
        defaultActionLabel = 'Apply Now';
      } else {
        defaultActionLabel = 'View Shift';
      }
    } else {
      defaultActionLabel = 'View Details';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Nursery Photo Header with Gradient & Badges (Stitch Pattern) ──
                SizedBox(
                  height: 145,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1B2A4A),
                          child: const Center(
                            child: Icon(Icons.child_care_rounded, size: 48, color: Colors.white24),
                          ),
                        ),
                      ),
                      // Smooth gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                            stops: const [0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                      // Badges top left
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 48,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (shift.requiredQualification.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1B2A4A).withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  shift.requiredQualification.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            if (shift.branchName.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.storefront_outlined, size: 11, color: Color(0xFF1D4ED8)),
                                    const SizedBox(width: 3),
                                    Text(
                                      shift.branchName,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Bookmark button top right
                      Positioned(
                        top: 8,
                        right: 10,
                        child: InkWell(
                          onTap: () => ref.read(bookmarkedShiftIdsProvider.notifier).toggle(shift.id),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Icon(
                              isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                              color: isBookmarked ? const Color(0xFF38BDF8) : Colors.white,
                              size: 17,
                            ),
                          ),
                        ),
                      ),
                      // Floating title & location on bottom of photo
                      Positioned(
                        bottom: 10,
                        left: 14,
                        right: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1)),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nurseryArea,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                shadows: const [
                                  Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Shift Details Body (Stitch Micro-metrics + Pay Row) ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Micro-metrics 2-Column Grid
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF2563EB)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Shift Time',
                                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          '$startFmt – $endFmt',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.timelapse_rounded, size: 16, color: Color(0xFF64748B)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Paid Hours',
                                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          '$hoursFormatted ($breakFormatted)',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 10),

                      // Pay & Action Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      '£${shift.payRate.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const Text(
                                      ' /hr',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '£${shift.effectiveGrossPay.toStringAsFixed(2)} total est.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPendingApproval)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Pending',
                                    style: TextStyle(
                                      color: Color(0xFFB45309),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else if (shift.status != ShiftStatus.open && isStaff)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ShiftStatusBadge(status: shift.status),
                                ),
                              FilledButton(
                                onPressed: onTap,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B2A4A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  minimumSize: const Size(0, 36),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  trailingLabel ?? defaultActionLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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
