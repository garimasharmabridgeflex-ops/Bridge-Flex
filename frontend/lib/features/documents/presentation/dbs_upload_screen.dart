import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/photo_source_sheet.dart';
import '../../../shared/widgets/primary_button.dart';
import '../domain/document_status.dart';

final documentStatusProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(documentsRepositoryProvider).fetchStatus();
});

/// The full documents checklist (dbs/id/qualification/first aid/right to
/// work) — full app spec profile-fields request: "documents, dbs, id,
/// qualifications, first aid, right to work". Keyed by [DocumentType] so the
/// checklist UI can show a status per type, not just the single
/// most-recent-of-any-type [documentStatusProvider] returns.
final myDocumentsProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(documentsRepositoryProvider).listMyDocuments();
});

class DbsUploadScreen extends ConsumerStatefulWidget {
  const DbsUploadScreen({super.key});

  @override
  ConsumerState<DbsUploadScreen> createState() => _DbsUploadScreenState();
}

class _DbsUploadScreenState extends ConsumerState<DbsUploadScreen> {
  File? _file;
  String? _filename;
  DocumentType _docType = DocumentType.dbsCertificate;
  bool _loading = false;

  Future<void> _pickFile() async {
    final picked = await pickImageWithSourceSheet(context, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      _file = File(picked.path);
      _filename = picked.name;
    });
  }

  Future<void> _upload() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (_file == null || user == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(documentsRepositoryProvider).uploadDocument(
            uid: user.uid,
            file: _file!,
            filename: _filename!,
            type: _docType,
          );
      ref.invalidate(ownProfileProvider);
      ref.invalidate(documentStatusProvider);
      ref.invalidate(myDocumentsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${documentTypeLabel(_docType)} submitted successfully for verification.')),
        );
        setState(() {
          _file = null;
          _filename = null;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myDocsAsync = ref.watch(myDocumentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents & Credentials')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your documents checklist', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            myDocsAsync.when(
              loading: () => const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Text('Could not load documents: $e'),
              data: (docs) => Column(
                children: allDocumentTypes
                    .map((t) => _ChecklistRow(type: t, info: docs[t]))
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Document type',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<DocumentType>(
              initialValue: _docType,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.folder_shared_outlined),
              ),
              items: allDocumentTypes.map((t) {
                return DropdownMenuItem(
                  value: t,
                  child: Text(documentTypeLabel(t), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _docType = val);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Upload a clear photo or document of your ${documentTypeLabel(_docType)}. It will be reviewed before your verification badges update.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                ),
                child: Column(
                  children: [
                    Icon(
                      _file == null ? Icons.cloud_upload_outlined : Icons.check_circle_outline_rounded,
                      size: 40,
                      color: _file == null ? scheme.onSurfaceVariant : AppColors.mint,
                    ).animate(target: _file == null ? 0 : 1).scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1, 1),
                        ),
                    const SizedBox(height: 12),
                    Text(
                      _filename ?? 'Tap to choose a photo',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_file != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Ready to submit — tap below to confirm',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Submit for review',
              loading: _loading,
              onPressed: _file == null ? null : _upload,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.type, required this.info});

  final DocumentType type;
  final DocumentStatusInfo? info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = info?.status ?? DocReviewStatus.none;
    final (color, icon, label) = switch (status) {
      DocReviewStatus.verified => (AppColors.mint, Icons.verified_rounded, 'Verified'),
      DocReviewStatus.pendingReview => (AppColors.amber, Icons.hourglass_top_rounded, 'Under review'),
      DocReviewStatus.rejected => (Theme.of(context).colorScheme.error, Icons.error_outline_rounded, 'Rejected'),
      DocReviewStatus.none => (scheme.onSurfaceVariant, Icons.radio_button_unchecked, 'Not submitted'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(documentTypeLabel(type), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}
