import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../domain/training_module.dart';

/// One training module: the video, the content outline, and the entry point to
/// its knowledge check.
class TrainingModuleScreen extends ConsumerWidget {
  const TrainingModuleScreen({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(trainingOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Training')),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't load this module",
            subtitle: 'Check your connection and try again.',
          ),
        ),
        data: (data) {
          final module = data.modules.where((m) => m.moduleId == moduleId).firstOrNull;
          if (module == null) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Module not available',
                subtitle: 'It may have been unpublished since you last opened the app.',
              ),
            );
          }
          return _ModuleBody(module: module);
        },
      ),
    );
  }
}

class _ModuleBody extends ConsumerStatefulWidget {
  const _ModuleBody({required this.module});

  final TrainingModule module;

  @override
  ConsumerState<_ModuleBody> createState() => _ModuleBodyState();
}

class _ModuleBodyState extends ConsumerState<_ModuleBody> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  /// Reported once per screen visit. The backend is idempotent about it, but
  /// there's no reason to POST on every frame near the end of the video.
  bool _reportedWatched = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final module = widget.module;
    try {
      final url = await ref.read(trainingRepositoryProvider).resolveVideoUrl(module);
      if (url == null) {
        // A module with no video is legitimate — content may be outline-only,
        // or the video may not have been produced yet. The outline and quiz
        // still work.
        if (mounted) setState(() => _loading = false);
        return;
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.addListener(_onTick);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || _reportedWatched || !c.value.isInitialized) return;
    final duration = c.value.duration;
    if (duration == Duration.zero) return;
    // "Watched" at 95% rather than exactly the end: the final frames often
    // aren't reached before playback stops, so requiring 100% would leave
    // people stuck having watched the whole thing.
    if (c.value.position >= duration * 0.95) {
      _reportedWatched = true;
      ref
          .read(trainingRepositoryProvider)
          .markVideoWatched(widget.module.moduleId)
          .then((_) => ref.invalidate(trainingOverviewProvider))
          .catchError((_) {
        // Non-fatal: this is a progress hint, not the completion record.
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        _VideoArea(
          loading: _loading,
          error: _error,
          controller: _controller,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          module.title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (module.purpose.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            module.purpose,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (module.isCompleted) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Completed — best score ${module.bestScore}/${module.totalQuestions}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (module.contentOutline.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            "What's covered",
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final line in module.contentOutline)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line, style: Theme.of(context).textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (module.hasQuiz)
          FilledButton.icon(
            onPressed: () => context.push('/training/${module.moduleId}/quiz'),
            icon: Icon(module.isCompleted ? Icons.refresh_rounded : Icons.quiz_rounded),
            label: Text(
              module.isCompleted
                  ? 'Retake knowledge check'
                  : 'Start knowledge check (${module.questions.length} questions)',
            ),
          )
        else
          Text(
            'A knowledge check for this module has not been added yet.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        if (module.hasQuiz) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You need ${module.passMark} of ${module.questions.length} correct to complete this module.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _VideoArea extends StatefulWidget {
  const _VideoArea({required this.loading, required this.error, required this.controller});

  final bool loading;
  final String? error;
  final VideoPlayerController? controller;

  @override
  State<_VideoArea> createState() => _VideoAreaState();
}

class _VideoAreaState extends State<_VideoArea> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = widget.controller;

    if (widget.loading) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (widget.error != null || controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  widget.error != null ? 'Video unavailable' : 'No video for this module',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(controller),
            // Deliberately a bespoke control strip rather than a packaged
            // player: the app styles every other surface itself, and these
            // are 60-second clips that need play/pause and a scrub bar,
            // nothing more.
            GestureDetector(
              onTap: () => setState(() {
                controller.value.isPlaying ? controller.pause() : controller.play();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: controller.value.isPlaying
                    ? Colors.transparent
                    : Colors.black.withValues(alpha: 0.25),
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: controller.value.isPlaying ? 0 : 1,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 32, color: Colors.black87),
                    ),
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ],
        ),
      ),
    );
  }
}
