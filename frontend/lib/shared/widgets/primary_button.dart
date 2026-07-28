import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: loading
          ? const SizedBox(
              key: ValueKey('loading'),
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Text(label),
              ],
            ),
    );

    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: color != null
          ? ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white)
          : null,
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
