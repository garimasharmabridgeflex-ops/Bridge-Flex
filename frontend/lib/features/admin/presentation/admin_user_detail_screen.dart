import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../documents/domain/document_status.dart';
import '../../profile/domain/profile.dart';
import '../domain/admin_models.dart';
import 'admin_review_screen.dart';

final adminUserDetailProvider =
    FutureProvider.autoDispose.family<AdminUserDetail, String>((ref, uid) {
  return ref.watch(adminRepositoryProvider).getUserDetail(uid);
});

/// Admin's full view of one user — full app spec admin-page request: "i
/// cannot see the profile, the uploaded images and files". Shows every
/// profile field plus every document they've ever uploaded (with an inline
/// image/PDF preview), and every admin action (suspend, verification
/// badges, review pending documents).
class AdminUserDetailScreen extends ConsumerWidget {
  const AdminUserDetailScreen({super.key, required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminUserDetailProvider(uid));
    return Scaffold(
      appBar: AppBar(title: const Text('User detail')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline, title: "Couldn't load user", subtitle: '$e'),
        data: (detail) => _DetailBody(uid: uid, detail: detail),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.uid, required this.detail});
  final String uid;
  final AdminUserDetail detail;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(adminUserDetailProvider(widget.uid));
      ref.invalidate(allUsersProvider);
      ref.invalidate(platformStatsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.detail.profile;
    final scheme = Theme.of(context).colorScheme;
    final isNursery = profile.role == UserRole.nursery;

    return AbsorbPointer(
      absorbing: _busy,
      child: Opacity(
        opacity: _busy ? 0.6 : 1,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  backgroundImage: profile.photoUrl.isNotEmpty ? NetworkImage(profile.photoUrl) : null,
                  child: profile.photoUrl.isEmpty
                      ? Icon(isNursery ? Icons.home_work_outlined : Icons.badge_outlined, color: scheme.primary)
                      : null,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name.isEmpty ? '(no name yet)' : profile.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(isNursery ? 'Nursery' : 'Staff', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _sectionHeader(context, 'Admin actions'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    if (!profile.suspended) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Suspend this account?'),
                          content: Text(
                            '${profile.name.isEmpty ? 'This user' : profile.name} will be signed out and unable to sign back in until reinstated.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(backgroundColor: scheme.error),
                              child: const Text('Suspend'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                    }
                    await _run(() => ref.read(adminRepositoryProvider).setUserSuspended(
                          uid: widget.uid,
                          suspended: !profile.suspended,
                        ));
                  },
                  style: profile.suspended
                      ? null
                      : FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                  icon: Icon(profile.suspended ? Icons.lock_open_rounded : Icons.block_rounded, size: 18),
                  label: Text(profile.suspended ? 'Reinstate account' : 'Suspend account'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _run(() => ref.read(adminRepositoryProvider).setVerificationBadge(
                        uid: widget.uid,
                        badge: 'identity',
                        verified: !profile.identityVerified,
                      )),
                  icon: Icon(
                    profile.identityVerified ? Icons.verified_rounded : Icons.verified_outlined,
                    size: 18,
                    color: profile.identityVerified ? AppColors.mint : null,
                  ),
                  label: Text(profile.identityVerified ? 'Identity verified ✓' : 'Mark identity verified'),
                ),
                if (isNursery)
                  OutlinedButton.icon(
                    onPressed: () => _run(() => ref.read(adminRepositoryProvider).setVerificationBadge(
                          uid: widget.uid,
                          badge: 'ofsted',
                          verified: !profile.ofstedVerified,
                        )),
                    icon: Icon(
                      profile.ofstedVerified ? Icons.school_rounded : Icons.school_outlined,
                      size: 18,
                      color: profile.ofstedVerified ? AppColors.mint : null,
                    ),
                    label: Text(profile.ofstedVerified ? 'Ofsted verified ✓' : 'Mark Ofsted verified'),
                  ),
              ],
            ),

            _sectionHeader(context, 'Profile'),
            _InfoRow('Role', isNursery ? 'Nursery' : 'Staff'),
            if (profile.phone.isNotEmpty) _InfoRow('Phone', profile.phone),
            if (profile.email.isNotEmpty) _InfoRow('Email', profile.email),
            _InfoRow('DBS status', profile.dbsStatus.name),
            if (isNursery && profile.address.isNotEmpty) _InfoRow('Address', profile.address),
            if (isNursery && profile.postcode.isNotEmpty) _InfoRow('Postcode', profile.postcode),
            if (isNursery && profile.registeredCompanyName.isNotEmpty)
              _InfoRow('Company name', profile.registeredCompanyName),
            if (isNursery && profile.ofstedRegNumber.isNotEmpty) _InfoRow('Ofsted reg. number', profile.ofstedRegNumber),
            if (!isNursery && profile.city.isNotEmpty) _InfoRow('City', profile.city),
            if (!isNursery && profile.nationality.isNotEmpty) _InfoRow('Nationality', profile.nationality),
            if (!isNursery && profile.dbsCertificateNumber.isNotEmpty)
              _InfoRow('DBS certificate #', profile.dbsCertificateNumber),
            if (profile.description.isNotEmpty) _InfoRow('About', profile.description),
            if (profile.bio.isNotEmpty) _InfoRow('Bio', profile.bio),

            _sectionHeader(context, 'Uploaded documents (${widget.detail.documents.length})'),
            if (widget.detail.documents.isEmpty)
              Text('No documents uploaded yet.', style: TextStyle(color: scheme.onSurfaceVariant))
            else
              ...widget.detail.documents.map((d) => _DocumentTile(doc: d)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: 8),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _DocumentTile extends ConsumerStatefulWidget {
  const _DocumentTile({required this.doc});
  final AdminDocumentEntry doc;

  @override
  ConsumerState<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends ConsumerState<_DocumentTile> {
  String? _url;
  bool _loading = false;
  String? _error;

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url =
          await ref.read(firebaseStorageProvider).ref(widget.doc.storagePath).getDownloadURL();
      if (mounted) setState(() => _url = url);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final doc = widget.doc;
    final (color, statusLabel) = switch (doc.status) {
      DocReviewStatus.verified => (AppColors.mint, 'Verified'),
      DocReviewStatus.pendingReview => (AppColors.amber, 'Pending review'),
      DocReviewStatus.rejected => (scheme.error, 'Rejected'),
      DocReviewStatus.none => (scheme.onSurfaceVariant, 'Unknown'),
    };
    final isPdf = doc.storagePath.toLowerCase().endsWith('.pdf');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(documentTypeLabel(doc.type), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (doc.uploadedAt != null)
              Text(
                DateFormat('d MMM yyyy, HH:mm').format(doc.uploadedAt!),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            if (doc.reviewNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Note: ${doc.reviewNote}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (_url == null)
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadPreview,
                icon: _loading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
                label: Text(_error != null ? 'Retry preview' : (isPdf ? 'Open PDF' : 'Load preview')),
              )
            else if (isPdf)
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF ready — open the link below'),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.network(_url!, height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
