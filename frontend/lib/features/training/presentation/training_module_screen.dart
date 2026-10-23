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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: const Text(
          'EYFS Training Module',
          style: TextStyle(
            fontSize: 17,
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
    if (c.value.position >= duration * 0.95) {
      _reportedWatched = true;
      ref
          .read(trainingRepositoryProvider)
          .markVideoWatched(widget.module.moduleId)
          .then((_) => ref.invalidate(trainingOverviewProvider))
          .catchError((_) {});
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
      children: [
        // ── Video Card ─────────────────────────────────────────────────────
        _VideoArea(
          loading: _loading,
          error: _error,
          controller: _controller,
        ),
        const SizedBox(height: 16),

        // ── Module Overview Card ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'EYFS STATUTORY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2563EB),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (module.isCompleted) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Text(
                            'Completed (${module.bestScore}/${module.totalQuestions})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                module.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              if (module.purpose.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  module.purpose,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Written Sections ───────────────────────────────────────────────
        if (module.sections.isNotEmpty) ...[
          for (final sec in module.sections) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sec.heading,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final para in sec.body)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        para,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF334155),
                          height: 1.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],

        // ── Content Outline Card ───────────────────────────────────────────
        if (module.contentOutline.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.sections.isEmpty ? "What's Covered" : 'Key Takeaways',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),
                for (final line in module.contentOutline)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2563EB),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF334155),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Knowledge Check Action Card ────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              if (module.hasQuiz) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.quiz_outlined,
                        color: Color(0xFF2563EB),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Knowledge Check',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${module.questions.length} questions • Pass mark ${module.passMark}/${module.questions.length}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/training/${module.moduleId}/quiz'),
                    icon: Icon(
                      module.isCompleted ? Icons.refresh_rounded : Icons.arrow_forward_rounded,
                      size: 16,
                    ),
                    label: Text(
                      module.isCompleted
                          ? 'Retake Knowledge Check'
                          : 'Start Knowledge Check (${module.questions.length} Questions)',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B2A4A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const Text(
                  'A knowledge check for this module has not been published yet.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        ),
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
    final controller = widget.controller;

    if (widget.loading) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
        ),
      );
    }

    if (widget.error != null || controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.ondemand_video_rounded, color: Colors.white38, size: 40),
                SizedBox(height: 8),
                Text(
                  'Reading & Outline Lesson',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              onTap: () => setState(() {
                controller.value.isPlaying ? controller.pause() : controller.play();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: controller.value.isPlaying
                    ? Colors.transparent
                    : Colors.black.withValues(alpha: 0.35),
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
                      child: const Icon(Icons.play_arrow_rounded, size: 30, color: Color(0xFF0F172A)),
                    ),
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              colors: const VideoProgressColors(
                playedColor: Color(0xFF2563EB),
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
