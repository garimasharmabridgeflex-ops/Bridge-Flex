import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/constants/profile_options.dart';
import '../../../shared/widgets/chip_multi_select.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../profile/domain/profile.dart';
import '../../ratings/presentation/rate_shift_sheet.dart';
import '../../timesheets/presentation/timesheet_card.dart';
import '../../home/presentation/home_shell.dart';
import '../data/bookmarks_provider.dart';
import '../domain/shift.dart';
import 'browse_shifts_screen.dart';
import 'my_shifts_screen.dart';
import 'widgets/shift_card.dart' show kDefaultNurseryPhotos;

final shiftDetailProvider = FutureProvider.autoDispose.family<Shift?, String>((ref, shiftId) {
  return ref.watch(shiftRepositoryProvider).fetchShift(shiftId);
});

class ShiftDetailScreen extends ConsumerStatefulWidget {
  const ShiftDetailScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  ConsumerState<ShiftDetailScreen> createState() => _ShiftDetailScreenState();
}

class _ShiftDetailScreenState extends ConsumerState<ShiftDetailScreen> {
  bool _busy = false;

  Future<void> _openChat(Shift shift) async {
    setState(() => _busy = true);
    try {
      final sessions = await ref.read(chatRepositoryProvider).fetchSessions();
      final match = sessions.where((s) => s.shiftId == shift.id).firstOrNull;
      if (match != null && mounted) {
        context.push('/chats/${match.id}');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat thread is created once a shift is booked.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(Shift shift) async {
    setState(() => _busy = true);
    try {
      await ref.read(shiftRepositoryProvider).applyForShift(shift.id);
      ref.invalidate(shiftDetailProvider(shift.id));
      ref.invalidate(openShiftsProvider);
      ref.invalidate(myShiftsProvider);
      if (mounted) {
        // Deliberately not "booked": the nursery still has to approve this,
        // and telling someone they have a shift they might not get would be
        // worse than the extra step of explaining.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Applied — the nursery will confirm before it's yours."),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decideApplicant(Shift shift, String staffId, bool approve) async {
    if (!approve) {
      // Declining is one-way — the applicant can't re-apply — so it gets a
      // confirmation step where approving doesn't.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Decline this applicant?'),
          content: const Text(
              "They'll be told the shift went to someone else and won't be able to apply again. "
              'The shift stays open for other staff.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Decline')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(shiftRepositoryProvider);
      if (approve) {
        await repo.approveApplicant(shiftId: shift.id, staffId: staffId);
      } else {
        await repo.rejectApplicant(shiftId: shift.id, staffId: staffId);
      }
      ref.invalidate(shiftDetailProvider(shift.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? 'Approved — they can now see the shift as booked and message you.'
                : 'Applicant declined.'),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reportNoShow(Shift shift, String staffId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report no-show?'),
        content: const Text(
            "This flags that the staff member didn't turn up for this shift — it feeds your nursery's no-show rate statistic."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(shiftRepositoryProvider).markNoShow(shiftId: shift.id, staffId: staffId);
      ref.invalidate(shiftDetailProvider(shift.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No-show reported.')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Shift shift, {required bool isStaffDroppingBookedShift}) async {
    final isNurseryRemovingOpenShift = !isStaffDroppingBookedShift && shift.status == ShiftStatus.open;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isStaffDroppingBookedShift
              ? 'Cancel your acceptance?'
              : isNurseryRemovingOpenShift
                  ? 'Remove this shift?'
                  : 'Cancel this shift?',
        ),
        content: Text(
          isStaffDroppingBookedShift
              ? 'The shift will reopen so someone else can take it. The nursery will be notified.'
              : isNurseryRemovingOpenShift
                  ? 'This shift has not been booked yet. Removing it will permanently take it off the marketplace.'
                  : 'This removes the shift from the marketplace entirely and cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(isNurseryRemovingOpenShift ? 'Remove shift' : 'Cancel shift'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(shiftRepositoryProvider).cancelShift(shift.id);
      ref.invalidate(shiftDetailProvider(shift.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            isStaffDroppingBookedShift
                ? 'Cancelled — the shift is open again for someone else.'
                : isNurseryRemovingOpenShift
                    ? 'Shift removed from marketplace.'
                    : 'Shift cancelled.',
          ),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openEditShiftSheet(BuildContext context, Shift shift) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditShiftSheet(shift: shift),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiftAsync = ref.watch(shiftDetailProvider(widget.shiftId));
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift details'),
        actions: [
          shiftAsync.whenOrNull(
            data: (shift) {
              if (shift != null && user?.uid == shift.nurseryId && shift.status == ShiftStatus.open) {
                return TextButton.icon(
                  onPressed: () => _openEditShiftSheet(context, shift),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                );
              }
              return null;
            },
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: shiftAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Failed to load', subtitle: '$e'),
        data: (shift) {
          if (shift == null) {
            return const EmptyState(icon: Icons.search_off_rounded, title: 'Shift not found');
          }

          final isOwner = user?.uid == shift.nurseryId;
          // Membership must check the full bookedStaffIds list, not just
          // bookedStaffId ("most recent acceptor") — on a multi-capacity
          // shift the first person to accept would otherwise be told
          // they're not part of it once someone else accepts too.
          final isBookedStaff = user != null && shift.isBookedBy(user.uid);
          final alreadyAccepted = isBookedStaff;
          final isInProgress = now.isAfter(shift.startTime) && now.isBefore(shift.endTime);
          final isDone = now.isAfter(shift.endTime);
          // Application state, distinct from booking: applying no longer
          // secures the shift, so someone waiting on a decision must not be
          // offered the apply button again, and must not be shown as booked.
          final hasApplied = user != null && shift.hasAppliedBy(user.uid);
          final wasDeclined = user != null && shift.wasRejectedFor(user.uid);

          final trainingAsync = ref.watch(trainingOverviewProvider);
          final trainingOverview = trainingAsync.valueOrNull;
          final hasIncompleteCourses = trainingOverview != null &&
              trainingOverview.totalCount > 0 &&
              !trainingOverview.allComplete;
          final isDbsVerified = profile?.dbsStatus == DbsStatus.verified;
          final isRightToWorkVerified = profile?.rightToWorkVerified == true;
          final isFirstAidVerified = (profile?.skills.any((s) => s.toLowerCase().contains('first aid')) ?? false) ||
              (profile?.qualifications.any((q) => q.toLowerCase().contains('first aid')) ?? false);
          final isQualPassed = profile != null && profile.qualificationLevel != QualificationLevel.none;
          final isEligible = !hasIncompleteCourses && isDbsVerified && isRightToWorkVerified;

          final canAccept = !isOwner &&
              !alreadyAccepted &&
              !hasApplied &&
              !wasDeclined &&
              shift.status == ShiftStatus.open &&
              profile?.role == UserRole.staff;
          final canCancel = (isOwner || isBookedStaff) &&
              shift.status != ShiftStatus.cancelled &&
              !isInProgress &&
              !isDone;
          final canRate = (isOwner || isBookedStaff) && isDone;
          final otherPartyId = isOwner ? shift.bookedStaffId : shift.nurseryId;

          final totalMinutes = shift.duration.inMinutes;
          final payableMinutes = (totalMinutes - shift.unpaidBreakMinutes).clamp(0, totalMinutes);
          final payableHours = (payableMinutes / 60.0).toStringAsFixed(1);
          final dateStr = DateFormat('EEEE, d MMMM yyyy').format(shift.startTime);
          final timeStr = '${DateFormat('HH:mm').format(shift.startTime)} – ${DateFormat('HH:mm').format(shift.endTime)}';
          final breakDisplay = shift.unpaidBreakMinutes > 0
              ? (shift.unpaidBreakMinutes % 60 == 0
                  ? '${shift.unpaidBreakMinutes ~/ 60}h unpaid break'
                  : '${shift.unpaidBreakMinutes}m unpaid break')
              : 'No break (fully paid)';

          final nurseryProfile = isOwner
              ? null
              : ref.watch(publicProfileProvider(shift.nurseryId)).valueOrNull;

          final nurseryPhotos = isOwner
              ? (profile?.photos ?? const <String>[])
              : (nurseryProfile?.photos ?? const <String>[]);
          final authenticHeroPhoto = nurseryPhotos.isNotEmpty
              ? nurseryPhotos.first
              : (isOwner ? profile?.photoUrl : nurseryProfile?.photoUrl)?.isNotEmpty == true
                  ? (isOwner ? profile!.photoUrl : nurseryProfile!.photoUrl)
                  : (isOwner ? profile?.logoUrl : nurseryProfile?.logoUrl)?.isNotEmpty == true
                      ? (isOwner ? profile!.logoUrl : nurseryProfile!.logoUrl)
                      : null;
          final heroPhotoUrl = authenticHeroPhoto ??
              kDefaultNurseryPhotos[shift.id.hashCode.abs() % kDefaultNurseryPhotos.length];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Card with Authentic Nursery Photo Background
                Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140F172A),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: Image.network(
                          heroPhotoUrl,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1B2A4A)),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.45),
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.85),
                              ],
                              stops: const [0.0, 0.4, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(AppRadius.pill),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      shift.requiredQualification.isNotEmpty
                                          ? shift.requiredQualification.replaceAll('_', ' ').toUpperCase()
                                          : 'EARLY YEARS COVER',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      ShiftStatusBadge(status: shift.status),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          ref.read(bookmarkedShiftIdsProvider.notifier).toggle(shift.id);
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.45),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            ref.watch(bookmarkedShiftIdsProvider).contains(shift.id)
                                                ? Icons.bookmark_rounded
                                                : Icons.bookmark_border_rounded,
                                            color: ref.watch(bookmarkedShiftIdsProvider).contains(shift.id)
                                                ? const Color(0xFF38BDF8)
                                                : Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    shift.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                      shadows: [
                                        Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (shift.branchName.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.storefront_outlined, size: 13, color: Colors.white),
                                          const SizedBox(width: 4),
                                          Text(
                                            shift.branchName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  Text(
                                    shift.room.isNotEmpty
                                        ? '${shift.room} • $dateStr'
                                        : dateStr,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      shadows: const [
                                        Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms),

                const SizedBox(height: 12),

                // Stitch 4-Column Key Metrics Card
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x060F172A),
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Metric 1: Rate
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '£${shift.payRate.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1B2A4A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Hourly Rate',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
                      // Metric 2: Total Pay
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '£${shift.effectiveGrossPay.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Total Pay',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
                      // Metric 3: Payable Hours
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${payableHours}h',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1B2A4A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Payable',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
                      // Metric 4: Ratio / Age Group
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              shift.ageGroup.isNotEmpty ? shift.ageGroup : '1:3',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1B2A4A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Room Ratio',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Schedule Card (Stitch pattern)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Color(0xFF2563EB),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1B2A4A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$timeStr • $breakDisplay',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Pay Breakdown Callout (Statutory 12.07% Holiday Pay)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF2563EB),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Decision 12 Compliant Rolled-up Holiday Pay',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1B2A4A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Gross rate of £${shift.payRate.toStringAsFixed(2)}/hr includes 12.07% statutory rolled-up holiday pay under UK Working Time Regulations.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // ── Stitch Alexandria Compliance & Eligibility Checklist ───
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x060F172A), blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Compliance & Eligibility',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1B2A4A),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isEligible ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isEligible ? 'Verified' : 'Action Required',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isEligible ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CompliancePill(
                            label: shift.requiredQualification.isNotEmpty
                                ? shift.requiredQualification
                                : 'Level 3 Early Years',
                            isPassed: isQualPassed,
                          ),
                          _CompliancePill(
                            label: 'Enhanced DBS Active',
                            isPassed: isDbsVerified,
                          ),
                          _CompliancePill(
                            label: 'Paediatric 1st Aid',
                            isPassed: isFirstAidVerified,
                          ),
                          _CompliancePill(
                            label: 'Right to Work UK',
                            isPassed: isRightToWorkVerified,
                          ),
                          _CompliancePill(
                            label: hasIncompleteCourses
                                ? 'Courses (${trainingOverview!.completedCount}/${trainingOverview.totalCount})'
                                : 'Training Complete',
                            isPassed: !hasIncompleteCourses,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),
                if (shift.requiredQualification.isNotEmpty)
                  _InfoTile(
                    icon: Icons.school_outlined,
                    label: 'Required qualification',
                    value: shift.requiredQualification,
                  ),
                if (shift.safeguardingNotes.isNotEmpty)
                  _InfoTile(
                    icon: Icons.security_rounded,
                    label: 'Safeguarding notes',
                    value: shift.safeguardingNotes,
                  ),
                if (shift.healthAndSafetyNotes.isNotEmpty)
                  _InfoTile(
                    icon: Icons.health_and_safety_outlined,
                    label: 'Health & Safety notes',
                    value: shift.healthAndSafetyNotes,
                  ),
                if (shift.capacity > 1)
                  _InfoTile(
                    icon: Icons.group_outlined,
                    label: 'Staff required',
                    value: '${shift.spotsFilled}/${shift.capacity} positions filled',
                  ),
                if (shift.ageGroup.isNotEmpty)
                  _InfoTile(icon: Icons.child_care_outlined, label: 'Age group', value: shift.ageGroup),
                if (shift.room.isNotEmpty)
                  _InfoTile(icon: Icons.door_front_door_outlined, label: 'Room', value: shift.room),
                if (shift.numberOfChildren > 0)
                  _InfoTile(
                    icon: Icons.groups_outlined,
                    label: 'Number of children',
                    value: '${shift.numberOfChildren}',
                  ),
                if (shift.expectedDuties.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Expected duties', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  ChipDisplayRow(values: shift.expectedDuties, options: shiftDutyOptions),
                ],
                if (shift.requirements.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Minimum requirements', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  ChipDisplayRow(values: shift.requirements, options: shiftRequirementOptions),
                ],
                if (shift.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Shift requirements & details', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(shift.description),
                  ),
                ],
                if (nurseryPhotos.length > 1) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Nursery setting photos', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: nurseryPhotos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          nurseryPhotos[i],
                          width: 120,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 120,
                            height: 90,
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                _PartyTile(uid: shift.nurseryId, label: 'Posted by Nursery'),
                for (final staffId in shift.bookedStaffIds) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _PartyTile(
                    uid: staffId,
                    label: shift.isMarkedNoShow(staffId) ? 'Booked Staff Member · No-show reported' : 'Booked Staff Member',
                  ),
                  if (isOwner && canRate) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => RateShiftSheet(shiftId: shift.id, rateeId: staffId),
                      ),
                      icon: const Icon(Icons.star_outline_rounded, size: 18, color: AppColors.amber),
                      label: const Text('Rate this staff member', style: TextStyle(color: AppColors.amber)),
                    ),
                  ],
                  if (isOwner && isDone && !shift.isMarkedNoShow(staffId)) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _reportNoShow(shift, staffId),
                      icon: const Icon(Icons.person_off_outlined, size: 18, color: AppColors.coral),
                      label: const Text('Report no-show', style: TextStyle(color: AppColors.coral)),
                    ),
                  ],
                ],
                if ((isOwner || isBookedStaff) && shift.status == ShiftStatus.booked) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _openChat(shift),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text('Chat with ${isOwner ? 'Staff' : 'Nursery'}'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TimesheetCard(
                    shift: shift,
                    isOwner: isOwner,
                    isBookedStaff: isBookedStaff,
                    onTimesheetChanged: () {
                      ref.invalidate(shiftDetailProvider(widget.shiftId));
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (isInProgress) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.hourglass_top_rounded, color: AppColors.amber, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Shift is currently in progress — cancellation disabled.',
                            style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (canAccept) ...[
                  if (hasIncompleteCourses) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.school_rounded, color: Color(0xFF2563EB), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Mandatory Courses Required',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'You have completed ${trainingOverview.completedCount} of ${trainingOverview.totalCount} required training courses. Complete all mandatory modules before applying for nursery shifts.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1E40AF),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              ref.read(homeShellTabIndexProvider.notifier).state = 3;
                              context.go('/home');
                            },
                            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                            label: const Text('Complete Training Courses', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const PrimaryButton(
                      label: 'Complete Courses to Apply',
                      icon: Icons.lock_outline_rounded,
                      loading: false,
                      onPressed: null,
                    ),
                  ] else if (!isDbsVerified || !isRightToWorkVerified) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.verified_user_outlined, color: Color(0xFFD97706), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Vetting Verification Pending',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  !isDbsVerified && !isRightToWorkVerified
                                      ? 'Your Enhanced DBS certificate and Right to Work documents must be approved before you can apply for shifts.'
                                      : (!isDbsVerified
                                          ? 'Your Enhanced DBS certificate must be approved before you can apply for shifts.'
                                          : 'Your Right to Work verification must be approved before you can apply for shifts.'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB45309),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const PrimaryButton(
                      label: 'Vetting Approval Required',
                      icon: Icons.lock_outline_rounded,
                      loading: false,
                      onPressed: null,
                    ),
                  ] else ...[
                    PrimaryButton(
                      label: 'Apply for shift',
                      icon: Icons.check_circle_outline_rounded,
                      loading: _busy,
                      onPressed: () => _apply(shift),
                    ).animate().fadeIn(duration: 250.ms).scale(
                          begin: const Offset(0.97, 0.97),
                          end: const Offset(1, 1),
                        ),
                  ],
                ],
                if (hasApplied) ...[
                  _StatusNotice(
                    icon: Icons.hourglass_top_rounded,
                    color: AppColors.amber,
                    text: 'Application sent — waiting for the nursery to confirm. '
                        'The shift stays open to others until they do.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (wasDeclined) ...[
                  _StatusNotice(
                    icon: Icons.info_outline_rounded,
                    color: Colors.grey,
                    text: 'This shift went to someone else.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                // Applicants list, nursery side. Placed with the actions
                // rather than the details because approving is the nursery's
                // main job on this screen once people start applying.
                if (isOwner && shift.pendingStaffIds.isNotEmpty) ...[
                  _ApplicantList(
                    shift: shift,
                    busy: _busy,
                    onApprove: (staffId) => _decideApplicant(shift, staffId, true),
                    onReject: (staffId) => _decideApplicant(shift, staffId, false),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                // Owner (nursery) rating is handled per booked-staff-member
                // above, since a multi-capacity shift can have more than one
                // ratee; only the staff→nursery direction has a single party.
                if (canRate && !isOwner) ...[
                  PrimaryButton(
                    label: 'Rate nursery',
                    icon: Icons.star_outline_rounded,
                    color: AppColors.amber,
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => RateShiftSheet(shiftId: shift.id, rateeId: otherPartyId!),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (isOwner && shift.status == ShiftStatus.open) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _openEditShiftSheet(context, shift),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit shift details'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (canCancel)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _cancel(
                                  shift,
                                  isStaffDroppingBookedShift:
                                      isBookedStaff && shift.status == ShiftStatus.booked,
                                ),
                        icon: Icon(
                          (isOwner && shift.status == ShiftStatus.open)
                              ? Icons.delete_outline_rounded
                              : Icons.close_rounded,
                        ),
                        label: Text(
                          isBookedStaff && shift.status == ShiftStatus.booked
                              ? 'Cancel my acceptance'
                              : (isOwner && shift.status == ShiftStatus.open)
                                  ? 'Remove shift'
                                  : 'Cancel shift',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _PartyTile extends ConsumerWidget {
  const _PartyTile({required this.uid, required this.label});

  final String uid;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicProfileAsync =
        ref.watch(publicProfileProvider(uid));
    return InkWell(
      onTap: () => context.push('/profile/$uid'),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: _InfoTile(
        icon: Icons.person_outline_rounded,
        label: label,
        value: publicProfileAsync.when(
          data: (p) => p?.name ?? 'View profile',
          loading: () => 'Loading…',
          error: (_, __) => 'View profile',
        ),
      ),
    );
  }
}


/// A short coloured banner for a shift's application state.
class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}



/// The nursery's decision list for a shift.
///
/// Each applicant is a tappable row through to their public profile — the
/// whole point of the approval step is that the setting looks at who they are
/// (training, DBS, experience) before committing cover to them.
class _ApplicantList extends ConsumerWidget {
  const _ApplicantList({
    required this.shift,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Shift shift;
  final bool busy;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_reg_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                shift.applicantCount == 1
                    ? '1 applicant awaiting your decision'
                    : '${shift.applicantCount} applicants awaiting your decision',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Approving fills ${shift.spotsRemaining == 1 ? 'the last place' : 'one of ${shift.spotsRemaining} places'}. '
            'Anyone still waiting is told the shift filled once it does.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final staffId in shift.pendingStaffIds) ...[
            _ApplicantRow(
              staffId: staffId,
              busy: busy,
              onApprove: () => onApprove(staffId),
              onReject: () => onReject(staffId),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ApplicantRow extends ConsumerWidget {
  const _ApplicantRow({
    required this.staffId,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final String staffId;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(publicProfileProvider(staffId));

    // The name may still be loading; the approve/decline controls stay usable
    // either way rather than being gated on a lookup that is only cosmetic.
    final name = profile.valueOrNull?.name ?? 'Applicant';
    final dbsVerified = profile.valueOrNull?.dbsBadge == DbsStatus.verified;
    final trainingCount = profile.valueOrNull?.trainingCompletedModuleIds.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push('/profile/$staffId'),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.person_rounded, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (dbsVerified)
                            const Text('DBS verified',
                                style: TextStyle(fontSize: 11.5, color: Colors.green)),
                          Text(
                            trainingCount > 0
                                ? '$trainingCount training module${trainingCount == 1 ? '' : 's'}'
                                : 'No training completed',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: trainingCount > 0 ? Colors.green : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompliancePill extends StatelessWidget {
  const _CompliancePill({required this.label, required this.isPassed});
  final String label;
  final bool isPassed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPassed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isPassed ? const Color(0xFF2563EB) : const Color(0xFFEF4444),
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditShiftSheet extends ConsumerStatefulWidget {
  const _EditShiftSheet({required this.shift});
  final Shift shift;

  @override
  ConsumerState<_EditShiftSheet> createState() => _EditShiftSheetState();
}

class _EditShiftSheetState extends ConsumerState<_EditShiftSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _payRateController;
  late final TextEditingController _roomController;
  late final TextEditingController _childrenController;
  late final TextEditingController _descriptionController;

  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late String _ageGroup;
  late int _unpaidBreakMinutes;
  late String _requiredQualification;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.shift.title);
    _payRateController = TextEditingController(text: widget.shift.payRate.toStringAsFixed(2));
    _roomController = TextEditingController(text: widget.shift.room);
    _childrenController = TextEditingController(
      text: widget.shift.numberOfChildren > 0 ? widget.shift.numberOfChildren.toString() : '',
    );
    _descriptionController = TextEditingController(text: widget.shift.description);

    _selectedDate = widget.shift.startTime;
    _startTime = TimeOfDay.fromDateTime(widget.shift.startTime);
    _endTime = TimeOfDay.fromDateTime(widget.shift.endTime);
    _ageGroup = widget.shift.ageGroup.isNotEmpty ? widget.shift.ageGroup : 'Toddlers (2-3 yrs)';
    _unpaidBreakMinutes = widget.shift.unpaidBreakMinutes;
    _requiredQualification = widget.shift.requiredQualification;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _payRateController.dispose();
    _roomController.dispose();
    _childrenController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final payRate = double.tryParse(_payRateController.text.trim());
    if (payRate == null || payRate < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid hourly rate (minimum £10.00)')),
      );
      return;
    }

    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    var endDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (endDateTime.isBefore(startDateTime)) {
      endDateTime = endDateTime.add(const Duration(days: 1));
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final numChildren = int.tryParse(_childrenController.text.trim()) ?? 0;

    setState(() => _saving = true);
    try {
      await ref.read(shiftRepositoryProvider).updateShift(
            shiftId: widget.shift.id,
            title: _titleController.text.trim(),
            date: dateStr,
            startTime: startDateTime,
            endTime: endDateTime,
            payRate: payRate,
            room: _roomController.text.trim(),
            ageGroup: _ageGroup,
            numberOfChildren: numChildren,
            description: _descriptionController.text.trim(),
            unpaidBreakMinutes: _unpaidBreakMinutes,
            requiredQualification: _requiredQualification,
          );

      ref.invalidate(shiftDetailProvider(widget.shift.id));
      ref.invalidate(myShiftsProvider);
      ref.invalidate(openShiftsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shift details updated successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Failed to update shift: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dateStr = DateFormat('EEE, d MMM yyyy').format(_selectedDate);
    final startStr =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Edit Shift Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B2A4A),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Title
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Shift Title / Role *',
                        hintText: 'e.g. Level 3 Nursery Practitioner',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
                    ),
                    const SizedBox(height: 14),
                    // Pay Rate
                    TextFormField(
                      controller: _payRateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Hourly Pay Rate (£/hr) *',
                        prefixText: '£ ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (v) {
                        final parsed = double.tryParse(v ?? '');
                        if (parsed == null || parsed <= 0) return 'Enter a valid rate';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    // Date & Times
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                              ),
                              child: Text(dateStr,
                                  style:
                                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickStartTime,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start Time',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.schedule_rounded, size: 20),
                              ),
                              child: Text(startStr,
                                  style:
                                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _pickEndTime,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End Time',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.schedule_rounded, size: 20),
                              ),
                              child: Text(endStr,
                                  style:
                                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Room & Number of Children
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _roomController,
                            decoration: const InputDecoration(
                              labelText: 'Room Name',
                              hintText: 'e.g. Toddler Room',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.meeting_room_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _childrenController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Children Count',
                              hintText: 'e.g. 12',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.groups_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Age Group Dropdown
                    DropdownButtonFormField<String>(
                      value: [
                        'Babies (0-2 yrs)',
                        'Toddlers (2-3 yrs)',
                        'Preschool (3-5 yrs)',
                        'Mixed Ages (0-5 yrs)',
                      ].contains(_ageGroup)
                          ? _ageGroup
                          : 'Toddlers (2-3 yrs)',
                      decoration: const InputDecoration(
                        labelText: 'Age Group',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.child_care_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Babies (0-2 yrs)', child: Text('Babies (0-2 yrs)')),
                        DropdownMenuItem(value: 'Toddlers (2-3 yrs)', child: Text('Toddlers (2-3 yrs)')),
                        DropdownMenuItem(value: 'Preschool (3-5 yrs)', child: Text('Preschool (3-5 yrs)')),
                        DropdownMenuItem(value: 'Mixed Ages (0-5 yrs)', child: Text('Mixed Ages (0-5 yrs)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _ageGroup = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    // Unpaid Break Dropdown
                    DropdownButtonFormField<int>(
                      value: [0, 15, 30, 45, 60].contains(_unpaidBreakMinutes) ? _unpaidBreakMinutes : 0,
                      decoration: const InputDecoration(
                        labelText: 'Unpaid Break Time',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.coffee_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('No break (fully paid)')),
                        DropdownMenuItem(value: 15, child: Text('15 minutes unpaid')),
                        DropdownMenuItem(value: 30, child: Text('30 minutes unpaid')),
                        DropdownMenuItem(value: 45, child: Text('45 minutes unpaid')),
                        DropdownMenuItem(value: 60, child: Text('1 hour unpaid')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _unpaidBreakMinutes = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    // Minimum Qualification Required
                    DropdownButtonFormField<String>(
                      value: [
                        '',
                        'unqualified',
                        'level_2',
                        'level_3',
                        'level_4_plus',
                        'eyts_qts',
                      ].contains(_requiredQualification)
                          ? _requiredQualification
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Required Qualification',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Any / No Minimum')),
                        DropdownMenuItem(value: 'unqualified', child: Text('Unqualified / Nursery Assistant')),
                        DropdownMenuItem(value: 'level_2', child: Text('Level 2 Early Years Practitioner')),
                        DropdownMenuItem(value: 'level_3', child: Text('Level 3 Early Years Educator')),
                        DropdownMenuItem(value: 'level_4_plus', child: Text('Level 4+ / Deputy / Room Leader')),
                        DropdownMenuItem(value: 'eyts_qts', child: Text('EYTS / QTS Qualified Teacher')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _requiredQualification = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    // Additional Details / Notes
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Requirements & Notes',
                        hintText: 'Any special instructions or room details...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B2A4A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



