import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/profile/domain/profile.dart';
import '../../features/shifts/domain/shift.dart';

class DbsBadge extends StatelessWidget {
  const DbsBadge({super.key, required this.status, this.compact = false});

  final DbsStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (status) {
      DbsStatus.verified => (AppColors.mint, 'DBS verified', Icons.verified_rounded),
      DbsStatus.pending => (AppColors.amber, 'DBS pending', Icons.hourglass_top_rounded),
      DbsStatus.unverified => (Colors.grey, 'DBS unverified', Icons.gpp_maybe_outlined),
    };
    return _Pill(color: color, label: compact ? label.split(' ').last : label, icon: icon);
  }
}

class ShiftStatusBadge extends StatelessWidget {
  const ShiftStatusBadge({super.key, required this.status});

  final ShiftStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (status) {
      ShiftStatus.open => (AppColors.mint, 'Open', Icons.event_available_rounded),
      ShiftStatus.booked => (AppColors.indigo, 'Booked', Icons.event_busy_rounded),
      ShiftStatus.cancelled => (Colors.grey, 'Cancelled', Icons.cancel_outlined),
    };
    return _Pill(color: color, label: label, icon: icon);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.label, required this.icon});

  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
