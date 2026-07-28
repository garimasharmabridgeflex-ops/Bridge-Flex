import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme.dart';

class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AppRadius.sm,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class ShiftCardSkeleton extends StatelessWidget {
  const ShiftCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            ShimmerBox(height: 18, width: 160),
            SizedBox(height: 12),
            ShimmerBox(height: 14, width: 220),
            SizedBox(height: 8),
            ShimmerBox(height: 14, width: 120),
          ],
        ),
      ),
    );
  }
}
