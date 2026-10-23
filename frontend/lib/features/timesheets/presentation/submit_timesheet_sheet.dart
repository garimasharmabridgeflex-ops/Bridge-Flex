import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
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

  void _adjustTime(bool isStart, int deltaMinutes) {
    final current = isStart ? _startTime : _endTime;
    final totalMins = (current.hour * 60 + current.minute + deltaMinutes + 1440) % 1440;
    setState(() {
      if (isStart) {
        _startTime = TimeOfDay(hour: totalMins ~/ 60, minute: totalMins % 60);
      } else {
        _endTime = TimeOfDay(hour: totalMins ~/ 60, minute: totalMins % 60);
      }
    });
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int get _elapsedMinutes {
    final start = _combineDateAndTime(_startDate, _startTime);
    var end = _combineDateAndTime(_startDate, _endTime);
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end.difference(start).inMinutes;
  }

  int get _calculatedBillableMinutes {
    final totalMins = _elapsedMinutes;
    final billable = totalMins - _breakMinutes;
    return billable > 0 ? billable : 0;
  }

  double get _calculatedGrossPay {
    final billable = _calculatedBillableMinutes;
    final hourlyRate = widget.shift.payRate;
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
            backgroundColor: Color(0xFF059669),
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
    final elapsedMins = _elapsedMinutes;

    final startStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final endStr = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Handle & Title
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existingTimesheet != null ? 'Resubmit Timesheet' : 'Submit Timesheet',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1B2A4A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Time Adjuster Cards (Stitch Pattern: Start & Finish)
            Row(
              children: [
                // Start Time Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SHIFT START',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: _startTime);
                            if (picked != null) setState(() => _startTime = picked);
                          },
                          child: Text(
                            startStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1B2A4A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _adjustTime(true, -15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '-15m',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () => _adjustTime(true, 15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '+15m',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // End Time Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SHIFT FINISH',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: _endTime);
                            if (picked != null) setState(() => _endTime = picked);
                          },
                          child: Text(
                            endStr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1B2A4A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _adjustTime(false, -15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '-15m',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: InkWell(
                                onTap: () => _adjustTime(false, 15),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '+15m',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ),
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

            const SizedBox(height: 12),

            // Statutory Break Segmented Pills (Stitch Pattern)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'STATUTORY UNPAID BREAK',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'UK WTR Compliant',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      children: [
                        for (final breakOption in [0, 30, 60])
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _breakMinutes = breakOption),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: _breakMinutes == breakOption ? const Color(0xFF1B2A4A) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Center(
                                  child: Text(
                                    breakOption == 0 ? '0 mins' : '$breakOption mins',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: _breakMinutes == breakOption ? Colors.white : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 4-Column Calculation Summary (Stitch Pattern)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  // Elapsed
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          (elapsedMins / 60.0).toStringAsFixed(2),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A)),
                        ),
                        const SizedBox(height: 2),
                        const Text('Elapsed', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFE2E8F0)),
                  // Break
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '-${(_breakMinutes / 60.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 2),
                        const Text('Break', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFE2E8F0)),
                  // Payable
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          (billableMins / 60.0).toStringAsFixed(2),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1B2A4A)),
                        ),
                        const SizedBox(height: 2),
                        const Text('Payable', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Container(height: 24, width: 1, color: const Color(0xFFE2E8F0)),
                  // Gross Est
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '£${_calculatedGrossPay.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF059669)),
                        ),
                        const SizedBox(height: 2),
                        const Text('Gross Est.', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 16),

            // Submit Button in Oxford Navy Pill
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2A4A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                elevation: 0,
              ),
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Submit Timesheet for Nursery Sign-off',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
