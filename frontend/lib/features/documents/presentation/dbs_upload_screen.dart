import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/live/live_refresh.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/photo_source_sheet.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../profile/domain/profile.dart';
import '../domain/document_status.dart';

final documentStatusProvider = FutureProvider.autoDispose((ref) {
  // Rides the live heartbeat: an admin approving the certificate (or asking
  // for more information) reaches the practitioner without a re-login.
  ref.watch(liveTickProvider);
  return ref.watch(documentsRepositoryProvider).fetchStatus();
});

/// Live stream of the caller's documents checklist — one listener on
/// `documents where uid == me` (the owner read the rules grant), so an
/// admin approval/rejection updates the checklist immediately instead of
/// waiting for the next polling tick.
final myDocumentsProvider = StreamProvider.autoDispose
    <Map<DocumentType, DocumentStatusInfo>>((ref) {
  final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (uid == null) {
    return Stream.value(const <DocumentType, DocumentStatusInfo>{});
  }
  return ref.watch(documentsRepositoryProvider).watchMyDocuments(uid);
});

class DbsUploadScreen extends ConsumerStatefulWidget {
  const DbsUploadScreen({super.key});

  @override
  ConsumerState<DbsUploadScreen> createState() => _DbsUploadScreenState();
}

class _DbsUploadScreenState extends ConsumerState<DbsUploadScreen> {
  // Active document type to submit
  DocumentType _docType = DocumentType.dbsCertificate;

  // DBS-specific fields
  final _dbsNumberController = TextEditingController();
  DateTime? _dbsIssueDate;
  bool _onUpdateService = false;

  // File upload state (web-safe)
  Uint8List? _fileBytes;
  String? _filename;
  bool _loading = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final profile = ref.read(ownProfileProvider).valueOrNull;
      if (profile != null) {
        if (profile.dbsCertificateNumber.isNotEmpty) {
          _dbsNumberController.text = profile.dbsCertificateNumber;
        }
        if (profile.dbsExpiryDate != null) {
          _dbsIssueDate = profile.dbsExpiryDate;
        }
      }
      _applyRecoveredPick();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _dbsNumberController.dispose();
    super.dispose();
  }

  /// Document uploads accept the original PDF as well as a photo scan, so
  /// the source sheet offers the system file dialog alongside camera/gallery.
  Future<void> _pickFile() async {
    final picked = await pickImageWithSourceSheet(context, imageQuality: 92, allowFiles: true);
    if (picked == null) return;
    await _usePickedFile(picked);
  }

  Future<void> _usePickedFile(XFile picked) async {
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    // The same contract storage.rules enforces (image/* or application/pdf,
    // under 10MB) — checked here so the user gets a plain-English message
    // instead of a Storage permission error after a long upload.
    final lower = picked.name.toLowerCase();
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.pdf'];
    if (!allowedExtensions.any(lower.endsWith)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a JPEG, PNG or PDF file.')),
      );
      return;
    }
    if (bytes.length > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file is over 10MB. Please upload a smaller scan or PDF.')),
      );
      return;
    }

    setState(() {
      _fileBytes = bytes;
      _filename = picked.name;
    });
  }

  /// Picks up a photo the OS recovered after it destroyed the app mid-capture
  /// (see captureLostPick), so the user does not have to take it again.
  void _applyRecoveredPick() {
    final recovered = ref.read(recoveredPickProvider);
    if (recovered == null) return;
    ref.read(recoveredPickProvider.notifier).state = null;
    _usePickedFile(recovered);
  }

  Future<void> _pickIssueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dbsIssueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365 * 10)),
      lastDate: now,
      helpText: 'Select DBS Certificate Issue Date',
    );
    if (picked != null) {
      setState(() => _dbsIssueDate = picked);
    }
  }

  Future<void> _submit() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    if (_fileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a photo or scan of your certificate.')),
      );
      return;
    }

    if (_docType == DocumentType.dbsCertificate) {
      final certNum = _dbsNumberController.text.trim();
      if (certNum.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid DBS Certificate Number.')),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      // 1. If DBS certificate, save metadata to user profile
      if (_docType == DocumentType.dbsCertificate) {
        await ref.read(profileRepositoryProvider).updateProfile(
              dbsCertificateNumber: _dbsNumberController.text.trim(),
              dbsExpiryDate: _dbsIssueDate ?? DateTime.now(),
            );
      }

      // 2. Upload file via web-safe bytes
      await ref.read(documentsRepositoryProvider).uploadDocument(
            uid: user.uid,
            bytes: _fileBytes!,
            // Real picks always carry their extension (a .pdf name is what
            // makes uploadDocument send application/pdf); this fallback only
            // fires when the picker returned no name, so assume the photo case.
            filename: _filename ?? 'document_${DateTime.now().millisecondsSinceEpoch}.jpg',
            type: _docType,
          );

      // Invalidate relevant providers to refresh UI state
      ref.invalidate(ownProfileProvider);
      ref.invalidate(documentStatusProvider);
      ref.invalidate(myDocumentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('${documentTypeLabel(_docType)} submitted successfully for verification!'),
          ),
        );
        setState(() {
          _fileBytes = null;
          _filename = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final myDocsAsync = ref.watch(myDocumentsProvider);
    final isDbsMode = _docType == DocumentType.dbsCertificate;
    final dbsVerified = profile?.dbsStatus == DbsStatus.verified;
    final dbsPending = profile?.dbsStatus == DbsStatus.pending;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Documents & DBS Verification',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Editorial Guidance Card ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x06000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          color: Color(0xFF2563EB),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Early Years Compliance',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'To accept nursery shifts, UK Early Years (EYFS) regulations require a verified Enhanced DBS certificate and identity checks. Please provide your certificate details and upload a clear photo or scan.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF475569),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Verification Checklist ───────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'YOUR CREDENTIALS STATUS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: myDocsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B2A4A)),
                  ),
                ),
                error: (e, _) => Text('Could not load documents: $e', style: const TextStyle(fontSize: 12, color: Colors.red)),
                data: (docs) => Column(
                  children: allDocumentTypes.map((t) {
                    final isDbsType = t == DocumentType.dbsCertificate;
                    DocReviewStatus status = docs[t]?.status ?? DocReviewStatus.none;
                    if (isDbsType) {
                      if (dbsVerified) status = DocReviewStatus.verified;
                      else if (dbsPending && status == DocReviewStatus.none) status = DocReviewStatus.pendingReview;
                    }
                    return _ChecklistRow(type: t, status: status);
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Submission Section ───────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'SUBMIT A DOCUMENT FOR VERIFICATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
            ),

            // Document Type Dropdown Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<DocumentType>(
                  value: _docType,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                  items: allDocumentTypes.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(
                            t == DocumentType.dbsCertificate
                                ? Icons.shield_rounded
                                : Icons.description_outlined,
                            size: 18,
                            color: const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            documentTypeLabel(t),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _docType = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // If DBS Certificate, render the DBS-specific inputs
            if (isDbsMode) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DBS Certificate Number',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '12-digit number located at the top right of your DBS certificate',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: _dbsNumberController,
                      label: '12-digit Certificate Number',
                      prefixIcon: Icons.badge_outlined,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Issue Date Picker
                    const Text(
                      'Certificate Issue Date',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickIssueDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _dbsIssueDate != null
                                    ? DateFormat('dd MMMM yyyy').format(_dbsIssueDate!)
                                    : 'Select issue date',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _dbsIssueDate != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                                  fontWeight: _dbsIssueDate != null ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Update Service Toggle
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DBS Update Service',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Subscribed on GOV.UK (allows annual instant checks)',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _onUpdateService,
                          activeColor: const Color(0xFF2563EB),
                          onChanged: (val) => setState(() => _onUpdateService = val),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => launchUrl(
                        Uri.parse('https://www.gov.uk/dbs-update-service'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF2563EB)),
                          SizedBox(width: 4),
                          Text(
                            'Open GOV.UK Update Service',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF2563EB),
                              fontWeight: FontWeight.w600,
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

            // Document File / Photo Upload Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload ${documentTypeLabel(_docType)} Document',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Take a clear photo or upload a PDF. Ensure all four corners and text are visible.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),

                  // Pick area
                  InkWell(
                    onTap: _pickFile,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _fileBytes != null ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                          style: BorderStyle.solid,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_fileBytes != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _fileBytes!,
                                height: 90,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.file_present_rounded,
                                  size: 48,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _filename ?? 'Document Selected',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Tap to choose another file',
                              style: TextStyle(fontSize: 11, color: Color(0xFF2563EB)),
                            ),
                          ] else ...[
                            const Icon(
                              Icons.cloud_upload_outlined,
                              size: 36,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap to Take Photo or Upload Document',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Supports JPEG, PNG or PDF up to 10MB',
                              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            PrimaryButton(
              label: isDbsMode ? 'Submit DBS for Verification' : 'Upload ${documentTypeLabel(_docType)}',
              icon: Icons.check_circle_outline_rounded,
              loading: _loading,
              onPressed: _fileBytes == null ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.type, required this.status});

  final DocumentType type;
  final DocReviewStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      DocReviewStatus.verified => (const Color(0xFF10B981), Icons.verified_rounded, 'Verified'),
      DocReviewStatus.pendingReview => (const Color(0xFFF59E0B), Icons.hourglass_top_rounded, 'Under review'),
      DocReviewStatus.rejected => (const Color(0xFFEF4444), Icons.error_outline_rounded, 'Rejected'),
      DocReviewStatus.none => (const Color(0xFF94A3B8), Icons.radio_button_unchecked, 'Not submitted'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              documentTypeLabel(type),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms);
  }
}
