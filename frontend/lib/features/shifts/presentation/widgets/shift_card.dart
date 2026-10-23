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
    final dateFmt = DateFormat('EEE, d MMM').format(shift.startTime);

    final totalMinutes = shift.duration.inMinutes;
    final payableMinutes = (totalMinutes - shift.unpaidBreakMinutes).clamp(0, totalMinutes);
    final payableHours = (payableMinutes / 60.0).toStringAsFixed(1);

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
    final nurseryArea = settingName.isNotEmpty && rawArea != 'Early Years Setting' && !rawArea.contains(settingName)
        ? '$settingName • $rawArea'
        : (settingName.isNotEmpty ? settingName : rawArea);
    final roomName = shift.room.isNotEmpty ? shift.room : 'EYFS Room';

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
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Nursery Authentic Thumbnail (76x76) ─────────────
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        photoUrl,
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 76,
                          height: 76,
                          color: const Color(0xFF1B2A4A),
                          child: const Center(
                            child: Icon(Icons.child_care_rounded, size: 32, color: Colors.white30),
                          ),
                        ),
                      ),
                    ),
                    if (shift.requiredQualification.isNotEmpty)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xCC0F172A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            shift.requiredQualification.replaceAll('_', ' ').toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // ── Shift Information ──────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line 1: Title + Pay Rate
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayTitle,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1B2A4A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '£${shift.payRate.toStringAsFixed(2)}/hr',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Line 2: Setting / Branch Name & Location
                      Row(
                        children: [
                          if (shift.branchName.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.storefront_outlined, size: 11, color: Color(0xFF2563EB)),
                                  const SizedBox(width: 3),
                                  Text(
                                    shift.branchName,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              nurseryArea,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Line 3: Chips (Date, Hours, Room)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(Icons.calendar_today_rounded, dateFmt),
                          _chip(Icons.schedule_rounded, '$startFmt–$endFmt (${payableHours}h)'),
                          if (shift.room.isNotEmpty)
                            _chip(Icons.meeting_room_outlined, shift.room),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Line 4: Action Buttons Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              if (isPendingApproval)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Pending Approval',
                                    style: TextStyle(
                                      color: Color(0xFFB45309),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else if (shift.status != ShiftStatus.open)
                                ShiftStatusBadge(status: shift.status)
                              else
                                Text(
                                  '£${shift.effectiveGrossPay.toStringAsFixed(2)} total est.',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              InkWell(
                                onTap: () => ref.read(bookmarkedShiftIdsProvider.notifier).toggle(shift.id),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                    color: isBookmarked ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
                                    size: 19,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: onTap,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B2A4A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  trailingLabel ?? defaultActionLabel,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
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

  static Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: const Color(0xFF64748B)),
          const SizedBox(width: 3.5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
