import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../domain/shift.dart';

String _postedAgo(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class ShiftCard extends StatefulWidget {
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
  State<ShiftCard> createState() => _ShiftCardState();
}

class _ShiftCardState extends State<ShiftCard> {
  bool _isBookmarked = false;

  @override
  Widget build(BuildContext context) {
    final shift = widget.shift;
    final startFmt = DateFormat('HH:mm').format(shift.startTime);
    final endFmt = DateFormat('HH:mm').format(shift.endTime);
    final dateFmt = DateFormat('EEE, d MMM').format(shift.startTime);

    final totalMinutes = shift.duration.inMinutes;
    final payableMinutes = (totalMinutes - shift.unpaidBreakMinutes).clamp(0, totalMinutes);
    final payableHours = (payableMinutes / 60.0).toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Card with Gradient & Badges
              Container(
                height: 104,
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card - 1)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1B2A4A),
                      Color(0xFF273E6B),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top badges row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                shift.requiredQualification.isNotEmpty
                                    ? shift.requiredQualification
                                    : 'Early Years Cover',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            if (widget.isPendingApproval) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD97706),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: const Text(
                                  'Awaiting Approval',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ] else if (shift.status != ShiftStatus.open) ...[
                              const SizedBox(width: 6),
                              ShiftStatusBadge(status: shift.status),
                            ],
                          ],
                        ),
                        InkWell(
                          onTap: () => setState(() => _isBookmarked = !_isBookmarked),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Title and Room details
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shift.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              dateFmt,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (shift.room.isNotEmpty) ...[
                              Text(
                                ' • ${shift.room}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Micro-metrics 2-Column Row (Clean Stitch Pattern)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    // Shift Time
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
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.access_time_rounded,
                                color: Color(0xFF2563EB),
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Shift Time',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '$startFmt – $endFmt',
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
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
                    ),
                    const SizedBox(width: 8),
                    // Paid Hours
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
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.hourglass_bottom_rounded,
                                color: Color(0xFF475569),
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Paid Hours',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '${payableHours}h (${shift.unpaidBreakMinutes}m break)',
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
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
                    ),
                  ],
                ),
              ),

              // Pay & Action Row (Clean divider, bold rate & pill button)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '£${shift.payRate.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const Text(
                              '/hr',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '£${shift.effectiveGrossPay.toStringAsFixed(2)} total (inc. holiday pay)',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: widget.onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B2A4A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                      child: Text(
                        widget.trailingLabel ?? 'View Shift',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
