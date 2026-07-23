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

class ShiftCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('EEE d MMM · HH:mm');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(Icons.home_work_outlined, color: scheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shift.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _postedAgo(shift.createdAt),
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  ShiftStatusBadge(status: shift.status),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    timeFmt.format(shift.startTime),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.hourglass_bottom_rounded, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '${shift.duration.inMinutes ~/ 60}h ${shift.duration.inMinutes % 60}m',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (shift.capacity > 1) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.group_outlined, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '${shift.spotsFilled}/${shift.capacity} positions filled',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
              if (shift.expectedDuties.isNotEmpty) ...[
                const SizedBox(height: 10),
                ChipDisplayRow(
                  values: shift.expectedDuties.take(3).toList(),
                  options: shiftDutyOptions,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '£${shift.payRate.toStringAsFixed(2)}/hr',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (trailingLabel != null)
                    Text(
                      trailingLabel!,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
