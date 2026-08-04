import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../shared/constants/profile_options.dart';
import '../../../../shared/widgets/chip_multi_select.dart';
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
  });

  final Shift shift;
  final VoidCallback onTap;
  final String? trailingLabel;

  @override
  State<ShiftCard> createState() => _ShiftCardState();
}

class _ShiftCardState extends State<ShiftCard> {
  bool _isBookmarked = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('EEE d MMM · HH:mm');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Logo/Avatar + Posted time + Bookmark icon
                Row(
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      // Was a hardcoded 'K' (left over from the KVision name),
                      // so every shift card showed a "K" avatar no matter which
                      // nursery posted it. ShiftCard only receives a Shift,
                      // which carries nurseryId but no nursery name, so there
                      // is no initial to derive here — a neutral mark is
                      // correct rather than a wrong letter.
                      child: const Center(
                        child: Icon(
                          Icons.child_care_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Posted ',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                _postedAgo(widget.shift.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.shift.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isBookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: _isBookmarked ? AppColors.primary : scheme.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _isBookmarked = !_isBookmarked),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Location, Duration & Capacity line
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.shift.room.isNotEmpty
                            ? '${widget.shift.room} • ${timeFmt.format(widget.shift.startTime)} (${widget.shift.duration.inMinutes ~/ 60}h ${widget.shift.duration.inMinutes % 60}m)'
                            : '${timeFmt.format(widget.shift.startTime)} (${widget.shift.duration.inMinutes ~/ 60}h ${widget.shift.duration.inMinutes % 60}m)',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ShiftStatusBadge(status: widget.shift.status),
                  ],
                ),
                if (widget.shift.capacity > 1) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.group_outlined, size: 14, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.shift.spotsFilled}/${widget.shift.capacity} positions filled',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),

                // Skill / Duties Pills
                if (widget.shift.expectedDuties.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: widget.shift.expectedDuties.take(3).map((duty) {
                      final option = shiftDutyOptions
                          .firstWhere(
                            (o) => o.value == duty,
                            orElse: () => ChipOption(duty, duty),
                          );
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],

                // Footer row: Job Type Chip + Rate
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        widget.shift.ageGroup.isNotEmpty
                            ? widget.shift.ageGroup
                            : 'Nursery Shift',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Rate / ',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '£${widget.shift.payRate.toStringAsFixed(2)}/hr',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
