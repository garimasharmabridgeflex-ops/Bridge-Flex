import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/primary_button.dart';

/// Shared chrome for every onboarding wizard step (full app spec §1.2/§1.3):
/// a step-progress bar, title/subtitle, scrollable body, and a footer with
/// Next (disabled until [canContinue]) plus an optional Skip.
class WizardStepScaffold extends StatelessWidget {
  const WizardStepScaffold({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onNext,
    required this.canContinue,
    this.nextLabel = 'Next',
    this.onSkip,
    this.loading = false,
    this.illustration,
    this.onBack,
  });

  final int stepIndex;
  final int stepCount;
  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback? onNext;
  final bool canContinue;
  final String nextLabel;
  final VoidCallback? onSkip;
  final bool loading;

  /// Steps past the first can go back — full app spec: users should be able
  /// to move back through a multi-step wizard, not just forward or bail out.
  final VoidCallback? onBack;

  /// Optional step illustration shown above the title — full app spec ask
  /// for onboarding to feel less like a bare form.
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && onBack != null) onBack!();
      },
      child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Row(
              children: [
                if (onBack != null) ...[
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Row(
                    children: List.generate(stepCount, (i) {
                      final active = i <= stepIndex;
                      return Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: i == stepCount - 1 ? 0 : 6),
                          decoration: BoxDecoration(
                            color: active ? scheme.primary : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (illustration != null) ...[
                    Center(child: illustration!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Text(
                    title,
                    style:
                        Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.08, end: 0),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ).animate().fadeIn(delay: 50.ms, duration: 250.ms),
                  const SizedBox(height: AppSpacing.xl),
                  body.animate().fadeIn(delay: 100.ms, duration: 250.ms),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                if (onSkip != null) ...[
                  TextButton(onPressed: loading ? null : onSkip, child: const Text('Skip for now')),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: PrimaryButton(
                    label: nextLabel,
                    loading: loading,
                    onPressed: canContinue ? onNext : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}
