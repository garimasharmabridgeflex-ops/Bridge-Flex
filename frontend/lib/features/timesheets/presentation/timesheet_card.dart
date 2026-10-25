import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../shifts/domain/shift.dart';
import '../domain/timesheet.dart';
import 'submit_timesheet_sheet.dart';

final shiftTimesheetProvider = StreamProvider.autoDispose.family<Timesheet?, String>((ref, shiftId) {
  final repo = ref.watch(timesheetRepositoryProvider);
  return repo.watchTimesheetForShift(shiftId).handleError((_, __) async* {
    final fallback = await repo.getTimesheet(shiftId: shiftId);
    yield fallback;
  });
});

class TimesheetCard extends ConsumerStatefulWidget {
  const TimesheetCard({
    super.key,
    required this.shift,
    required this.isOwner,
    required this.isBookedStaff,
    required this.onTimesheetChanged,
  });

  final Shift shift;
  final bool isOwner;
  final bool isBookedStaff;
  final VoidCallback onTimesheetChanged;

  @override
  ConsumerState<TimesheetCard> createState() => _TimesheetCardState();
}

class _TimesheetCardState extends ConsumerState<TimesheetCard> {
  bool _actionBusy = false;

  void _openSubmitSheet(Timesheet? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SubmitTimesheetSheet(
        shift: widget.shift,
        existingTimesheet: existing,
        onSubmitted: () {
          ref.invalidate(shiftTimesheetProvider(widget.shift.id));
          widget.onTimesheetChanged();
        },
      ),
    );
  }

  Future<void> _approveTimesheet(Timesheet ts) async {
    final feedbackCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Timesheet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Approve ${ts.billableHoursFormatted} for this shift? Total charge: ${ts.nurseryChargeFormatted}.'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: feedbackCtrl,
              decoration: const InputDecoration(
                labelText: 'Optional feedback for practitioner',
                hintText: 'e.g. Great work today!',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('Confirm Approval'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await ref.read(timesheetRepositoryProvider).approveTimesheet(
            timesheetId: ts.id,
            feedback: feedbackCtrl.text.trim(),
          );
      ref.invalidate(shiftTimesheetProvider(widget.shift.id));
      widget.onTimesheetChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Timesheet approved!'), backgroundColor: AppColors.teal),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to approve: $e')));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _requestCorrection(Timesheet ts) async {
    final feedbackCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Timesheet Correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Explain the discrepancy so the practitioner can review and resubmit their hours:'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: feedbackCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Correction details *',
                hintText: 'e.g. Practitioner left 30 minutes early at 16:30.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (feedbackCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
            child: const Text('Send Correction Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await ref.read(timesheetRepositoryProvider).requestCorrection(
            timesheetId: ts.id,
            feedback: feedbackCtrl.text.trim(),
          );
      ref.invalidate(shiftTimesheetProvider(widget.shift.id));
      widget.onTimesheetChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Correction request sent.'), backgroundColor: AppColors.amber),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to request correction: $e')));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _disputeTimesheet(Timesheet ts) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report Issue / Dispute Hours'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Disputed timesheets are escalated directly to K Flex admin investigation. '
              'Please provide a detailed explanation:',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Dispute reason *',
                hintText: 'e.g. Staff did not attend the agreed shift / unverified hours.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            child: const Text('Submit Dispute'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await ref.read(timesheetRepositoryProvider).disputeTimesheet(
            timesheetId: ts.id,
            reason: reasonCtrl.text.trim(),
          );
      ref.invalidate(shiftTimesheetProvider(widget.shift.id));
      widget.onTimesheetChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dispute submitted. K Flex administration will investigate.'),
            backgroundColor: AppColors.coral,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to dispute: $e')));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Color _statusColor(TimesheetStatus status) {
    switch (status) {
      case TimesheetStatus.approved:
      case TimesheetStatus.adminApproved:
        return AppColors.teal;
      case TimesheetStatus.correctionRequested:
        return AppColors.amber;
      case TimesheetStatus.disputed:
        return AppColors.coral;
      case TimesheetStatus.submitted:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timesheetAsync = ref.watch(shiftTimesheetProvider(widget.shift.id));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: timesheetAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Error loading timesheet: $e', style: const TextStyle(fontSize: 12)),
          data: (ts) {
            // Case 1: No timesheet recorded yet
            if (ts == null) {
              if (widget.isBookedStaff) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.edit_calendar_rounded, color: AppColors.teal),
                        SizedBox(width: 8),
                        Text('Timesheet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ready to submit your hours for this completed shift? '
                      'Record your actual start, finish and break to receive prompt payment.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _openSubmitSheet(null),
                      icon: const Icon(Icons.add_task_rounded, size: 18),
                      label: const Text('Submit Timesheet'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                    ),
                  ],
                );
              } else if (widget.isOwner) {
                return Row(
                  children: const [
                    Icon(Icons.pending_actions_rounded, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Awaiting practitioner timesheet submission.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            }

            // Case 2: Timesheet exists
            final statusColor = _statusColor(ts.status);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.receipt_long_rounded, color: AppColors.teal),
                        SizedBox(width: 8),
                        Text('Timesheet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        ts.status.label,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Actual Hours:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          Text(
                            '${TimeOfDay.fromDateTime(ts.actualStartTime).format(context)} – ${TimeOfDay.fromDateTime(ts.actualEndTime).format(context)}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Unpaid Break:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          Text('${ts.unpaidBreakMinutes} mins', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Billable Hours:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          Text(
                            ts.billableHoursFormatted,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.isOwner ? 'Nursery Charge:' : 'Total Gross Pay:',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.isOwner ? ts.nurseryChargeFormatted : ts.grossPayFormatted,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (ts.nurseryFeedback.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Nursery note: ${ts.nurseryFeedback}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                if (ts.disputeReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.coral.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Dispute reason: ${ts.disputeReason}',
                      style: const TextStyle(fontSize: 12, color: AppColors.coral),
                    ),
                  ),
                ],
                if (ts.adminNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Admin note: ${ts.adminNotes}',
                      style: const TextStyle(fontSize: 12, color: AppColors.teal),
                    ),
                  ),
                ],
                // Practitioner Resubmit button on correction requested
                if (widget.isBookedStaff && ts.isCorrectionRequested) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _openSubmitSheet(ts),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: const Text('Resubmit Corrected Hours'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
                  ),
                ],
                // Nursery Actions when Timesheet is pending review
                if (widget.isOwner && ts.isPendingReview) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _actionBusy ? null : () => _approveTimesheet(ts),
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text('Approve'),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.teal),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _actionBusy ? null : () => _requestCorrection(ts),
                          child: const Text('Correct', style: TextStyle(color: AppColors.amber)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _actionBusy ? null : () => _disputeTimesheet(ts),
                        icon: const Icon(Icons.report_problem_outlined, color: AppColors.coral),
                        tooltip: 'Dispute Hours',
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
