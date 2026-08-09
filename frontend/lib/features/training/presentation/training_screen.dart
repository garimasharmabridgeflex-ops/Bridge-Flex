import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../domain/training_module.dart';

/// Training tab — the practitioner's module list and progress.
///
/// Modules come from Firestore rather than being compiled in, so this screen
/// makes no assumption about how many exist: the spec ships two now and seven
/// more across later phases.
class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(trainingOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Training')),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load training",
            subtitle: 'Check your connection and pull down to try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(trainingOverviewProvider),
              child: const Text('Retry'),
            ),
          ),
        ),
        data: (data) {
          if (data.modules.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: EmptyState(
                icon: Icons.school_outlined,
                title: 'No modules yet',
                subtitle: 'Training modules will appear here as they are published.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(trainingOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xl * 3,
              ),
              children: [
                _ProgressHeader(overview: data),
                const SizedBox(height: AppSpacing.lg),
                for (final m in data.modules) ...[
                  _ModuleCard(module: m),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.overview});

  final TrainingOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = overview.totalCount == 0
        ? 0.0
        : overview.completedCount / overview.totalCount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overview.allComplete ? Icons.verified_rounded : Icons.school_rounded,
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  overview.allComplete
                      ? 'All training complete'
                      : '${overview.completedCount} of ${overview.totalCount} complete',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            overview.allComplete
                ? 'Nurseries can see this on your profile when you apply for a shift.'
                : 'Completing these helps nurseries approve you faster.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final TrainingModule module;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completed = module.isCompleted;
    final started = module.status == TrainingStatus.inProgress;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.push('/training/${module.moduleId}'),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: completed
                  ? Colors.green.withValues(alpha: 0.4)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: completed
                      ? Colors.green.withValues(alpha: 0.12)
                      : scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: completed
                      ? const Icon(Icons.check_rounded, color: Colors.green)
                      : Text(
                          '${module.order}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                            fontSize: 17,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (module.purpose.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        module.purpose,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (module.videoDurationSeconds > 0)
                          _Pill(
                            icon: Icons.play_circle_outline_rounded,
                            label: '${module.videoDurationSeconds}s video',
                          ),
                        if (module.hasQuiz)
                          _Pill(
                            icon: Icons.quiz_outlined,
                            label: '${module.questions.length} questions',
                          ),
                        if (completed)
                          const _Pill(
                            icon: Icons.verified_rounded,
                            label: 'Completed',
                            tone: _PillTone.success,
                          )
                        else if (started)
                          const _Pill(
                            icon: Icons.timelapse_rounded,
                            label: 'In progress',
                            tone: _PillTone.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PillTone { neutral, success, warning }

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.tone = _PillTone.neutral});

  final IconData icon;
  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      _PillTone.success => Colors.green,
      _PillTone.warning => Colors.orange,
      _PillTone.neutral => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
