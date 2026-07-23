import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../shared/widgets/app_brand_mark.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: const AppBrandMark(size: 96).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
              duration: 700.ms,
              curve: Curves.easeInOut,
              begin: const Offset(0.92, 0.92),
              end: const Offset(1.04, 1.04),
            ),
      ),
    );
  }
}
