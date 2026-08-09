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
import '../domain/shift.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isStaffDroppingBookedShift ? 'Cancel your acceptance?' : 'Cancel this shift?'),
        content: Text(
          isStaffDroppingBookedShift
              ? 'The shift will reopen so someone else can take it. The nursery will be notified.'
              : 'This removes the shift from the marketplace entirely and cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Cancel shift'),
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

  @override
  Widget build(BuildContext context) {
    final shiftAsync = ref.watch(shiftDetailProvider(widget.shiftId));
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('Shift details')),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shift.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ShiftStatusBadge(status: shift.status),
                  ],
                ).animate().fadeIn(duration: 300.ms),
                const SizedBox(height: AppSpacing.lg),
                _InfoTile(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value: DateFormat('EEEE d MMMM yyyy').format(shift.startTime),
                ),
                _InfoTile(
                  icon: Icons.schedule_rounded,
                  label: 'Time',
                  value:
                      '${DateFormat('HH:mm').format(shift.startTime)} – ${DateFormat('HH:mm').format(shift.endTime)}'
                      ' (${shift.duration.inMinutes ~/ 60}h ${shift.duration.inMinutes % 60}m)',
                ),
                _InfoTile(
                  icon: Icons.payments_rounded,
                  label: 'Pay',
                  value:
                      '£${shift.payRate.toStringAsFixed(2)}/hr · est. total £${shift.totalPay.toStringAsFixed(2)}',
                  valueColor: AppColors.coral,
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
                if (canAccept)
                  PrimaryButton(
                    label: 'Apply for shift',
                    icon: Icons.check_circle_outline_rounded,
                    loading: _busy,
                    onPressed: () => _apply(shift),
                  ).animate().fadeIn(duration: 250.ms).scale(
                        begin: const Offset(0.97, 0.97),
                        end: const Offset(1, 1),
                      ),
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
                        icon: const Icon(Icons.close_rounded),
                        label: Text(
                          isBookedStaff && shift.status == ShiftStatus.booked
                              ? 'Cancel my acceptance'
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
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

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
                      ?.copyWith(fontWeight: FontWeight.w600, color: valueColor),
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
