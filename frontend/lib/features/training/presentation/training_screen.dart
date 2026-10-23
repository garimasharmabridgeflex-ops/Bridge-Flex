import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../domain/training_module.dart';

/// Training tab — the practitioner's module list and progress.
class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(trainingOverviewProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Training & Compliance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: overview.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Color(0xFF1B2A4A),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load training",
            subtitle: 'Check your connection and pull down to try again.',
            action: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1B2A4A),
              ),
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
            color: const Color(0xFF1B2A4A),
            onRefresh: () async => ref.invalidate(trainingOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _ProgressHeader(overview: data),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    'EYFS MANDATORY MODULES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                for (final m in data.modules) ...[
                  _ModuleCard(module: m),
                  const SizedBox(height: 12),
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
    final fraction = overview.totalCount == 0
        ? 0.0
        : overview.completedCount / overview.totalCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2A4A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x301B2A4A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      overview.allComplete ? Icons.verified_rounded : Icons.school_rounded,
                      color: overview.allComplete ? const Color(0xFF10B981) : const Color(0xFF60A5FA),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Training Progress',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        overview.allComplete
                            ? 'All Modules Complete'
                            : '${overview.completedCount} of ${overview.totalCount} Modules Done',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: overview.allComplete
                      ? const Color(0xFF10B981).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: overview.allComplete
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  overview.allComplete ? 'Ready to Book' : '${(fraction * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: overview.allComplete ? const Color(0xFF34D399) : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            overview.allComplete
                ? 'Your profile is fully verified for EYFS mandatory training across UK nurseries.'
                : 'All modules are required before you can apply for and confirm shifts.',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFCBD5E1),
              height: 1.35,
            ),
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
    final completed = module.isCompleted;
    final started = module.status == TrainingStatus.inProgress;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: completed
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/training/${module.moduleId}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: completed
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: completed
                          ? const Color(0xFF10B981).withValues(alpha: 0.25)
                          : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Center(
                    child: completed
                        ? const Icon(Icons.check_rounded, color: Color(0xFF059669), size: 22)
                        : Text(
                            '${module.order}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2563EB),
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (module.purpose.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          module.purpose,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
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
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
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
    final (bg, fg) = switch (tone) {
      _PillTone.success => (const Color(0xFFECFDF5), const Color(0xFF059669)),
      _PillTone.warning => (const Color(0xFFFFFBEB), const Color(0xFFD97706)),
      _PillTone.neutral => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

