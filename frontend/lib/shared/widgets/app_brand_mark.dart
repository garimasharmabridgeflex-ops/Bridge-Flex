import 'package:flutter/material.dart';

/// The K Vision logo mark — cropped from the source brand asset, transparent
/// background so it sits cleanly on any surface/theme.
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 44, this.withWordmark = false});

  final double size;
  final bool withWordmark;

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset(
      'assets/branding/logo_mark.png',
      height: size,
      width: size,
    );
    if (!withWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text(
          'K Vision',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
