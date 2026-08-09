import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../domain/admin_training_module.dart';

/// Authoring screen for one training module — content, sections and the
/// knowledge check.
///
/// Everything here is editable at runtime by design: the training spec expects
/// question wording and routine timings to change, and shipping an app release
/// to fix a typo in a quiz would be absurd.
class AdminTrainingEditScreen extends ConsumerStatefulWidget {
  const AdminTrainingEditScreen({super.key, required this.module, required this.isNew});

  final AdminTrainingModule module;
  final bool isNew;

  @override
  ConsumerState<AdminTrainingEditScreen> createState() => _AdminTrainingEditScreenState();
}

class _AdminTrainingEditScreenState extends ConsumerState<AdminTrainingEditScreen> {
  late final AdminTrainingModule m = widget.module;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (m.title.trim().isEmpty) {
      setState(() => _error = 'A title is required.');
      return;
    }
    if (m.moduleId.trim().isEmpty) {
      setState(() => _error = 'A module id is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminTrainingRepositoryProvider).upsert(m);
      ref.invalidate(adminTrainingModulesProvider);
      // Practitioners read a different endpoint, so its cache has to be
      // dropped too or an admin sees their edit and nobody else does.
      ref.invalidate(trainingOverviewProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // The backend validates option counts, answer indexes and the
      // no-questions-when-published rule; surface its message rather than
      // duplicating those rules here and letting the two drift.
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New module' : 'Edit module'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          _Label('Module id'),
          TextFormField(
            initialValue: m.moduleId,
            // Changing an id on an existing module would create a second
            // document rather than rename the first, orphaning everyone's
            // completion record against the old id.
            enabled: widget.isNew,
            decoration: InputDecoration(
              hintText: 'module-3-choking-safety',
              helperText: widget.isNew
                  ? 'Permanent. Used as the document id and in completion records.'
                  : 'Fixed after creation — completion records point at it.',
            ),
            onChanged: (v) => m.moduleId = v.trim(),
          ),
          const SizedBox(height: AppSpacing.md),

          _Label('Title'),
          TextFormField(
            initialValue: m.title,
            decoration: const InputDecoration(hintText: 'What a UK Nursery Looks Like'),
            onChanged: (v) => m.title = v,
          ),
          const SizedBox(height: AppSpacing.md),

          _Label('Purpose'),
          TextFormField(
            initialValue: m.purpose,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'One or two sentences on what this module is for.'),
            onChanged: (v) => m.purpose = v,
          ),
          const SizedBox(height: AppSpacing.md),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Order'),
                    TextFormField(
                      initialValue: '${m.order}',
                      keyboardType: TextInputType.number,
                      onChanged: (v) => m.order = int.tryParse(v) ?? m.order,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Video length (s)'),
                    TextFormField(
                      initialValue: '${m.videoDurationSeconds}',
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          m.videoDurationSeconds = int.tryParse(v) ?? m.videoDurationSeconds,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _Label('Video storage path'),
          TextFormField(
            initialValue: m.videoStoragePath,
            decoration: const InputDecoration(
              hintText: 'training-videos/module-3.mp4',
              helperText: 'Path in Firebase Storage. Re-uploading over the same path swaps the '
                  'video for everyone without editing this module.',
              helperMaxLines: 3,
            ),
            onChanged: (v) => m.videoStoragePath = v.trim(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Teaching sections ──────────────────────────────────────────
          _SectionHeader(
            title: 'Lesson content',
            subtitle: 'Headed sections of prose — this is what practitioners read.',
            onAdd: () => setState(() => m.sections.add(AdminTrainingSection())),
          ),
          for (var i = 0; i < m.sections.length; i++)
            _SectionEditor(
              key: ValueKey('section-$i-${m.sections.length}'),
              section: m.sections[i],
              index: i,
              onRemove: () => setState(() => m.sections.removeAt(i)),
              onChanged: () => setState(() {}),
            ),
          const SizedBox(height: AppSpacing.lg),

          // ── Questions ──────────────────────────────────────────────────
          _SectionHeader(
            title: 'Knowledge check',
            subtitle: 'A module is only marked complete when a practitioner passes this.',
            onAdd: () => setState(() {
              m.questions.add(AdminTrainingQuestion(id: 'q${m.questions.length + 1}'));
            }),
          ),
          if (m.questions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No questions yet. A module cannot be published without at least one.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          for (var i = 0; i < m.questions.length; i++)
            _QuestionEditor(
              key: ValueKey('question-$i-${m.questions.length}'),
              question: m.questions[i],
              index: i,
              onRemove: () => setState(() => m.questions.removeAt(i)),
              onChanged: () => setState(() {}),
            ),
          const SizedBox(height: AppSpacing.md),

          _Label('Pass mark (correct answers needed)'),
          TextFormField(
            initialValue: '${m.passMark}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              helperText: m.passMark == 0
                  ? 'Leave 0 to default to 80% of ${m.questions.length} questions, rounded up.'
                  : 'Out of ${m.questions.length} questions.',
              helperMaxLines: 2,
            ),
            onChanged: (v) => setState(() => m.passMark = int.tryParse(v) ?? 0),
          ),
          const SizedBox(height: AppSpacing.md),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: m.published,
            title: const Text('Published'),
            subtitle: Text(
              m.published
                  ? 'Visible to every practitioner.'
                  : 'Hidden from practitioners — safe to draft here.',
            ),
            onChanged: (v) => setState(() => m.published = v),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle, required this.onAdd});

  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(subtitle,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add',
          ),
        ],
      ),
    );
  }
}

class _SectionEditor extends StatelessWidget {
  const _SectionEditor({
    super.key,
    required this.section,
    required this.index,
    required this.onRemove,
    required this.onChanged,
  });

  final AdminTrainingSection section;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Section ${index + 1}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 12.5)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: onRemove,
                tooltip: 'Remove section',
              ),
            ],
          ),
          TextFormField(
            initialValue: section.heading,
            decoration: const InputDecoration(labelText: 'Heading'),
            onChanged: (v) => section.heading = v,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < section.body.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: section.body[i],
                      maxLines: null,
                      decoration: InputDecoration(labelText: 'Paragraph ${i + 1}'),
                      onChanged: (v) => section.body[i] = v,
                    ),
                  ),
                  if (section.body.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                      onPressed: () {
                        section.body.removeAt(i);
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () {
              section.body.add('');
              onChanged();
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add paragraph'),
          ),
        ],
      ),
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    super.key,
    required this.question,
    required this.index,
    required this.onRemove,
    required this.onChanged,
  });

  final AdminTrainingQuestion question;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Question ${index + 1}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary, fontSize: 12.5)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: onRemove,
                tooltip: 'Remove question',
              ),
            ],
          ),
          TextFormField(
            initialValue: question.id,
            decoration: const InputDecoration(
              labelText: 'Question id',
              helperText: 'Unique within this module. Answers are submitted against it.',
              helperMaxLines: 2,
            ),
            onChanged: (v) => question.id = v.trim(),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            initialValue: question.prompt,
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Question'),
            onChanged: (v) => question.prompt = v,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Options — tap the circle to mark the correct answer',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          for (var i = 0; i < question.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      question.correctIndex == i
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: question.correctIndex == i ? Colors.green : scheme.onSurfaceVariant,
                    ),
                    tooltip: 'Mark as the correct answer',
                    onPressed: () {
                      question.correctIndex = i;
                      onChanged();
                    },
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: question.options[i],
                      decoration: InputDecoration(labelText: 'Option ${i + 1}'),
                      onChanged: (v) => question.options[i] = v,
                    ),
                  ),
                  if (question.options.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                      onPressed: () {
                        question.options.removeAt(i);
                        // Keep the answer pointing at a real option: removing
                        // the option that was marked correct would otherwise
                        // leave an index past the end, which the backend
                        // rejects and which reads as "no answer is right".
                        if (question.correctIndex >= question.options.length) {
                          question.correctIndex = question.options.length - 1;
                        }
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () {
              question.options.add('');
              onChanged();
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add option'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            initialValue: question.explanation,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: 'Explanation (optional)',
              helperText: 'Shown after a practitioner passes, alongside the correct answer.',
              helperMaxLines: 2,
            ),
            onChanged: (v) => question.explanation = v,
          ),
        ],
      ),
    );
  }
}
