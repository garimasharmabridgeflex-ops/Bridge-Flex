import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../../shifts/domain/shift.dart';
import '../domain/timesheet.dart';

class SubmitTimesheetSheet extends ConsumerStatefulWidget {
  const SubmitTimesheetSheet({
    super.key,
    required this.shift,
    this.existingTimesheet,
    required this.onSubmitted,
  });

  final Shift shift;
  final Timesheet? existingTimesheet;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<SubmitTimesheetSheet> createState() => _SubmitTimesheetSheetState();
}

class _SubmitTimesheetSheetState extends ConsumerState<SubmitTimesheetSheet> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _breakMinutes;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingTimesheet;
    if (existing != null) {
      _startDate = existing.actualStartTime;
      _startTime = TimeOfDay.fromDateTime(existing.actualStartTime);
      _endTime = TimeOfDay.fromDateTime(existing.actualEndTime);
      _breakMinutes = existing.unpaidBreakMinutes;
    } else {
      _startDate = widget.shift.startTime;
      _startTime = TimeOfDay.fromDateTime(widget.shift.startTime);
      _endTime = TimeOfDay.fromDateTime(widget.shift.endTime);
      _breakMinutes = widget.shift.unpaidBreakMinutes;
    }
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int get _calculatedBillableMinutes {
    final start = _combineDateAndTime(_startDate, _startTime);
    var end = _combineDateAndTime(_startDate, _endTime);
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }
    final totalMins = end.difference(start).inMinutes;
    final billable = totalMins - _breakMinutes;
    return billable > 0 ? billable : 0;
  }

  double get _calculatedGrossPay {
    final billable = _calculatedBillableMinutes;
    final hourlyRate = widget.shift.effectivePayRate;
    return (billable / 60.0) * hourlyRate;
  }

  Future<void> _submit() async {
    final start = _combineDateAndTime(_startDate, _startTime);
    var end = _combineDateAndTime(_startDate, _endTime);
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }

    if (!end.isAfter(start)) {
      setState(() => _errorMessage = 'End time must be after start time');
      return;
    }

    final totalMins = end.difference(start).inMinutes;
    if (_breakMinutes >= totalMins) {
      setState(() => _errorMessage = 'Break minutes cannot exceed total shift length');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      await ref.read(timesheetRepositoryProvider).submitTimesheet(
            shiftId: widget.shift.id,
            actualStartTime: start,
            actualEndTime: end,
            unpaidBreakMinutes: _breakMinutes,
          );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSubmitted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timesheet submitted successfully! Awaiting nursery review.'),
            backgroundColor: AppColors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final billableMins = _calculatedBillableMinutes;
    final hours = billableMins ~/ 60;
    final mins = billableMins % 60;
    final timeFormatted = mins == 0 ? '${hours}h' : '${hours}h ${mins}m';

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_rounded, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.existingTimesheet != null
                      ? 'Resubmit Corrected Hours'
                      : 'Submit Timesheet',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (widget.existingTimesheet?.nurseryFeedback.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.coral.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nursery feedback / correction note:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.coral),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.existingTimesheet!.nurseryFeedback,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Record your actual working hours and unpaid break duration below:',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _startTime,
                    );
                    if (picked != null) {
                      setState(() => _startTime = picked);
                    }
                  },
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                  label: Text('Start: ${_startTime.format(context)}'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _endTime,
                    );
                    if (picked != null) {
                      setState(() => _endTime = picked);
                    }
                  },
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text('End: ${_endTime.format(context)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Text('Unpaid Break: ', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              DropdownButton<int>(
                value: _breakMinutes,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('0 mins')),
                  DropdownMenuItem(value: 15, child: Text('15 mins')),
                  DropdownMenuItem(value: 30, child: Text('30 mins')),
                  DropdownMenuItem(value: 45, child: Text('45 mins')),
                  DropdownMenuItem(value: 60, child: Text('60 mins')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _breakMinutes = val);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Billable Hours', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(timeFormatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Estimated Gross Pay', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      '£${_calculatedGrossPay.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.teal),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.coral, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: widget.existingTimesheet != null ? 'Resubmit Timesheet' : 'Confirm & Submit Timesheet',
            loading: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}
