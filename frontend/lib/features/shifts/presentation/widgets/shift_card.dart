import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../domain/shift.dart';


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

    final displayTitle = shift.title.isNotEmpty ? shift.title : 'Early Years Practitioner Cover';
    final nurseryArea = (shift.nurseryArea?.isNotEmpty ?? false) ? shift.nurseryArea! : 'Central Manchester';
    final roomName = shift.room.isNotEmpty ? shift.room : 'Baby Room';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Nursery Visual Header (Stitch Alexandria Pattern) ───────
              Container(
                height: 164,
                width: double.infinity,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1B2A4A),
                      Color(0xFF1E3A5F),
                      Color(0xFF2563EB),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // Subtle background decorative radial glow
                    Positioned(
                      right: -30,
                      top: -30,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    // Gradient overlay to guarantee high-contrast text readability
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Top Badges & Bookmark Row
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  shift.requiredQualification.isNotEmpty
                                      ? shift.requiredQualification
                                      : 'Priority Cover',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Ofsted: Outstanding',
                                  style: TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (widget.isPendingApproval) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD97706),
                                    borderRadius: BorderRadius.circular(20),
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
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
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
                    ),
                    // Floating Nursery Title & Subtitle at lower edge
                    Positioned(
                      bottom: 12,
                      left: 14,
                      right: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              shadows: [
                                Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$nurseryArea • $roomName • $dateFmt',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              shadows: const [
                                Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
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

              // ── Micro-metrics 2-Column Row (Stitch Pattern) ─────────────
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
                                size: 15,
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
                                size: 15,
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

              // ── Pay & Action Row (Large Rate, Total + Pill CTA) ─────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
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
                                fontSize: 19,
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
                          '£${shift.effectiveGrossPay.toStringAsFixed(2)} Total (inc. 12.07% holiday pay)',
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
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                      child: Text(
                        widget.trailingLabel ?? 'Book Shift',
                        style: const TextStyle(
                          fontSize: 12.5,
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
