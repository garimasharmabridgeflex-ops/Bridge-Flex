import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../domain/training_module.dart';

/// Knowledge check for one module.
///
/// Answers are graded by the backend — this screen never knows which option is
/// correct until a result comes back, and only sees the correct answers at all
/// once the module has been passed.
class TrainingQuizScreen extends ConsumerWidget {
  const TrainingQuizScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(trainingOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge check')),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load the questions",
            subtitle: 'Check your connection and try again.',
          ),
        ),
        data: (data) {
          final module = data.modules.where((m) => m.moduleId == moduleId).firstOrNull;
          if (module == null || !module.hasQuiz) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: EmptyState(
                icon: Icons.quiz_outlined,
                title: 'No questions available',
                subtitle: 'This module does not have a knowledge check yet.',
              ),
            );
          }
          return _QuizForm(module: module);
        },
      ),
    );
  }
}

class _QuizForm extends ConsumerStatefulWidget {
  const _QuizForm({required this.module});

  final TrainingModule module;

  @override
  ConsumerState<_QuizForm> createState() => _QuizFormState();
}

class _QuizFormState extends ConsumerState<_QuizForm> {
  final Map<String, int> _answers = {};
  bool _submitting = false;
  QuizResult? _result;
  String? _error;

  bool get _allAnswered => _answers.length == widget.module.questions.length;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(trainingRepositoryProvider)
          .submitQuiz(widget.module.moduleId, _answers);
      ref.invalidate(trainingOverviewProvider);
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not submit your answers. Check your connection and try again.';
        _submitting = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _answers.clear();
      _result = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return _ResultView(module: widget.module, result: result, onRetry: _retry);
    }

    final module = widget.module;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                'Answer all ${module.questions.length} questions. '
                'You need ${module.passMark} correct to complete this module.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (var i = 0; i < module.questions.length; i++) ...[
                _QuestionCard(
                  index: i,
                  question: module.questions[i],
                  selected: _answers[module.questions[i].id],
                  onSelect: (v) => setState(() => _answers[module.questions[i].id] = v),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _allAnswered && !_submitting ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _allAnswered
                          ? 'Submit answers'
                          : '${_answers.length} of ${module.questions.length} answered',
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final int index;
  final TrainingQuestion question;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question ${index + 1}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            question.prompt,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < question.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? scheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected == i
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: 0.6),
                      width: selected == i ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected == i
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: selected == i ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(question.options[i])),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.module, required this.result, required this.onRetry});

  final TrainingModule module;
  final QuizResult result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final passed = result.passed;
    final color = passed ? Colors.green : Colors.orange;

    // Questions are matched to results by id rather than position — the
    // backend returns one result per question in the module, and relying on
    // order would break silently if that ever changed.
    final byId = {for (final r in result.results) r.questionId: r};

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Icon(
                passed ? Icons.verified_rounded : Icons.refresh_rounded,
                size: 42,
                color: color,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                passed ? 'Module complete' : 'Not quite yet',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'You scored ${result.score} out of ${result.total} '
                '(${result.passMark} needed)',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (passed) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Nurseries can now see this on your profile.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < module.questions.length; i++) ...[
          _ResultRow(
            index: i,
            question: module.questions[i],
            result: byId[module.questions[i].id],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.md),
        if (!passed)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          )
        else
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to module'),
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.index, required this.question, required this.result});

  final int index;
  final TrainingQuestion question;
  final QuizQuestionResult? result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final correct = result?.correct ?? false;
    final correctIndex = result?.correctIndex;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 20,
            color: correct ? Colors.green : scheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1}. ${question.prompt}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                // correctIndex is only present once the module is passed, so
                // a failed attempt shows what was wrong without giving away
                // the answers for the retry.
                if (correctIndex != null &&
                    correctIndex >= 0 &&
                    correctIndex < question.options.length) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Answer: ${question.options[correctIndex]}',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
                if ((result?.explanation ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    result!.explanation,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
