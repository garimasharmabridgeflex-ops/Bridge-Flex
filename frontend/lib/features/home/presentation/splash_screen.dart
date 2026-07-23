import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/app_brand_mark.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppBrandMark(size: 64)
                // Entrance: pop in from small + faded, then settle —
                // distinct from the (barely-visible) 12%-scale idle pulse
                // this previously relied on alone, which read as "no
                // animation" when the splash route is only mounted briefly.
                .animate()
                .scale(
                  duration: 450.ms,
                  curve: Curves.easeOutBack,
                  begin: const Offset(0.4, 0.4),
                  end: const Offset(1, 1),
                )
                .fadeIn(duration: 300.ms)
                // Idle loop once settled: a visible breathing pulse plus a
                // gentle rotation wobble, so any extra time on this screen
                // still reads as alive rather than static.
                .then()
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  duration: 900.ms,
                  curve: Curves.easeInOut,
                  begin: const Offset(0.94, 0.94),
                  end: const Offset(1.08, 1.08),
                )
                .rotate(begin: -0.02, end: 0.02),
            const SizedBox(height: AppSpacing.md),
            Text(
              'K Vision',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }
}
