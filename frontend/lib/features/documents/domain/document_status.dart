import 'package:cloud_firestore/cloud_firestore.dart';

/// The `documents/{docId}.status` value from the backend — distinct from
/// `profiles.dbsStatus` (the profile-level badge derived from this).
enum DocReviewStatus { none, pendingReview, verified, rejected }

DocReviewStatus docReviewStatusFromString(String value) => switch (value) {
      'pending_review' => DocReviewStatus.pendingReview,
      'verified' => DocReviewStatus.verified,
      'rejected' => DocReviewStatus.rejected,
      _ => DocReviewStatus.none,
    };

/// The full staff "documents checklist" set backend/documents.go accepts —
/// full app spec profile-fields request: "documents, dbs, id, qualifications,
/// first aid, right to work".
enum DocumentType { dbsCertificate, cv, id, qualification, firstAid, rightToWork }

String documentTypeToApiString(DocumentType type) => switch (type) {
      DocumentType.dbsCertificate => 'dbs_certificate',
      DocumentType.cv => 'cv',
      DocumentType.id => 'id',
      DocumentType.qualification => 'qualification',
      DocumentType.firstAid => 'first_aid',
      DocumentType.rightToWork => 'right_to_work',
    };

DocumentType documentTypeFromString(String? value) => switch (value) {
      'cv' => DocumentType.cv,
      'id' => DocumentType.id,
      'qualification' => DocumentType.qualification,
      'first_aid' => DocumentType.firstAid,
      'right_to_work' => DocumentType.rightToWork,
      _ => DocumentType.dbsCertificate,
    };

String documentTypeLabel(DocumentType type) => switch (type) {
      DocumentType.dbsCertificate => 'DBS certificate',
      DocumentType.cv => 'CV / experience',
      DocumentType.id => 'Photo ID',
      DocumentType.qualification => 'Qualification certificate',
      DocumentType.firstAid => 'Paediatric first aid certificate',
      DocumentType.rightToWork => 'Right to work document',
    };

const List<DocumentType> allDocumentTypes = [
  DocumentType.dbsCertificate,
  DocumentType.cv,
  DocumentType.id,
  DocumentType.qualification,
  DocumentType.firstAid,
  DocumentType.rightToWork,
];

class DocumentStatusInfo {
  const DocumentStatusInfo({
    required this.status,
    this.type = DocumentType.dbsCertificate,
    this.docId,
    this.reviewNote,
    this.uploadedAt,
  });

  final DocReviewStatus status;
  final DocumentType type;
  final String? docId;
  final String? reviewNote;
  final DateTime? uploadedAt;

  bool get hasUploaded => status != DocReviewStatus.none;

  factory DocumentStatusInfo.fromJson(Map<String, dynamic> json) {
    return DocumentStatusInfo(
      status: docReviewStatusFromString(json['status'] as String? ?? 'none'),
      type: documentTypeFromString(json['type'] as String?),
      docId: json['docId'] as String?,
      reviewNote: (json['reviewNote'] as String?)?.isNotEmpty == true
          ? json['reviewNote'] as String
          : null,
      uploadedAt: json['uploadedAt'] != null
          ? DateTime.tryParse(json['uploadedAt'] as String)?.toLocal()
          : null,
    );
  }

  /// Maps a live Firestore `documents/{docId}` doc — the doc id plays the
  /// part the API injects as `docId`, and `uploadedAt` is a Firestore
  /// Timestamp here where the HTTP mirror serialises it as a string.
  factory DocumentStatusInfo.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final uploaded = data['uploadedAt'];
    return DocumentStatusInfo(
      status: docReviewStatusFromString(data['status'] as String? ?? 'none'),
      type: documentTypeFromString(data['type'] as String?),
      docId: doc.id,
      reviewNote: (data['reviewNote'] as String?)?.isNotEmpty == true
          ? data['reviewNote'] as String
          : null,
      uploadedAt: uploaded is Timestamp
          ? uploaded.toDate().toLocal()
          : uploaded is String
              ? DateTime.tryParse(uploaded)?.toLocal()
              : null,
    );
  }
}

/// One entry in the admin review queue — backend/documents.go
/// listPendingDocuments. Distinct from [DocumentStatusInfo] (the caller's
/// own document) since this carries whose document it is.
class PendingDocument {
  const PendingDocument({
    required this.docId,
    required this.uid,
    required this.type,
    required this.storagePath,
    this.uploadedAt,
  });

  final String docId;
  final String uid;
  final DocumentType type;
  final String storagePath;
  final DateTime? uploadedAt;

  factory PendingDocument.fromJson(Map<String, dynamic> json) => PendingDocument(
        docId: json['docId'] as String,
        uid: json['uid'] as String,
        type: documentTypeFromString(json['type'] as String?),
        storagePath: json['storagePath'] as String? ?? '',
        uploadedAt: json['uploadedAt'] != null
            ? DateTime.tryParse(json['uploadedAt'] as String)?.toLocal()
            : null,
      );
}
