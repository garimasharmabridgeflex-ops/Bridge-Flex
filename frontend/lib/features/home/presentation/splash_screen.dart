import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/app_brand_mark.dart';

/// Splash previously had no way out if the app got stuck here — router.dart
/// waits on a chain of auth/profile providers before it'll navigate away,
/// and every one of those has since been given its own timeout/fallback.
/// This is the last line of defense on top of those: if none of that
/// resolves things within [_stuckAfter], show a manual "sign out and
/// retry" escape hatch rather than leaving the user stranded with no
/// recourse but force-quitting the app.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _stuckAfter = Duration(seconds: 12);

  bool _showRetry = false;
  bool _retrying = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_stuckAfter, () {
      if (mounted) setState(() => _showRetry = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(firebaseAuthProvider).signOut();
    } catch (_) {
      // Best-effort — even if sign-out itself fails, falling through lets
      // the user see the retry button again rather than hanging silently.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

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
              'KFlex',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
            ).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
            if (_showRetry) ...[
              const SizedBox(height: AppSpacing.xl),
              Text(
                'This is taking longer than usual.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _retrying ? null : _retry,
                child: Text(_retrying ? 'Retrying…' : 'Retry'),
              ),
            ].animate().fadeIn(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
