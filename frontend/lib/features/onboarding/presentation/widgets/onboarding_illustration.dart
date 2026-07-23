import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../app/theme.dart';

/// A self-contained animated illustration for a wizard step — no external
/// asset/Lottie dependency, built entirely from shapes + icons so it has
/// zero network/asset-pipeline risk, but still gives onboarding real motion
/// instead of a static form.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    super.key,
    required this.icon,
    required this.color,
    this.satellites = const [],
    this.size = 148,
  });

  final IconData icon;
  final Color color;
  final List<IconData> satellites;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft glow backdrop, gently breathing.
          Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02)],
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                duration: 2200.ms,
                curve: Curves.easeInOut,
                begin: const Offset(0.92, 0.92),
                end: const Offset(1.06, 1.06),
              ),

          // Dashed-feel outer ring, slowly rotating.
          SizedBox(
            height: size * 0.86,
            width: size * 0.86,
            child: CustomPaint(painter: _DashedRingPainter(color: color.withValues(alpha: 0.35))),
          ).animate(onPlay: (c) => c.repeat()).rotate(duration: 12000.ms, begin: 0, end: 1),

          // Orbiting satellite icons.
          for (var i = 0; i < satellites.length; i++)
            _Satellite(
              angleOffset: (i / satellites.length) * 2 * math.pi,
              radius: size * 0.42,
              delayMs: i * 220,
              color: color,
              icon: satellites[i],
            ),

          // Central badge.
          Container(
            height: size * 0.46,
            width: size * 0.46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.22)!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.22),
          )
              .animate()
              .scale(duration: 400.ms, curve: Curves.easeOutBack, begin: const Offset(0.6, 0.6), end: const Offset(1, 1))
              .then()
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(duration: 1600.ms, curve: Curves.easeInOut, begin: 0, end: -6),
        ],
      ),
    );
  }
}

class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.angleOffset,
    required this.radius,
    required this.delayMs,
    required this.color,
    required this.icon,
  });

  final double angleOffset;
  final double radius;
  final int delayMs;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dx = radius * 0.98 * math.cos(angleOffset);
    final dy = radius * 0.7 * math.sin(angleOffset);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Container(
        height: 34,
        width: 34,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Icon(icon, size: 16, color: color),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(delay: delayMs.ms, duration: 1800.ms, curve: Curves.easeInOut, begin: -4, end: 4)
          .fadeIn(duration: 300.ms),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final radius = size.width / 2;
    const dashCount = 28;
    const gapFraction = 0.45;
    for (var i = 0; i < dashCount; i++) {
      final startAngle = (i / dashCount) * 2 * math.pi;
      final sweep = (2 * math.pi / dashCount) * (1 - gapFraction);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(radius, radius), radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) => oldDelegate.color != color;
}
