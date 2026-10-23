import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/document_status.dart';

class DocumentsRepository {
  DocumentsRepository(this._api, this._storage);

  final ApiClient _api;
  final FirebaseStorage _storage;

  Future<DocumentStatusInfo> fetchStatus() async {
    final res = await _api.post(ApiFunction.getDocumentStatus);
    return DocumentStatusInfo.fromJson(res);
  }

  /// The full documents checklist — one status entry per type the caller
  /// has ever uploaded (backend/documents.go listMyDocuments), keyed by
  /// [DocumentType] for the checklist UI (dbs/id/qualification/first
  /// aid/right to work).
  Future<Map<DocumentType, DocumentStatusInfo>> listMyDocuments() async {
    final res = await _api.post(ApiFunction.listMyDocuments);
    final list = (res['documents'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final out = <DocumentType, DocumentStatusInfo>{};
    for (final entry in list) {
      final info = DocumentStatusInfo.fromJson(entry);
      out[info.type] = info;
    }
    return out;
  }

  /// Uploads to `dbs-documents/{uid}/{filename}` (the prefix Storage rules
  /// and /createDocument both validate — ARCHITECTURE.md v2 §2) then
  /// registers the metadata doc, which also flips `dbsStatus` to `pending`.
  Future<void> uploadDbsCertificate({
    required String uid,
    File? file,
    Uint8List? bytes,
    required String filename,
  }) => uploadDocument(
        uid: uid,
        file: file,
        bytes: bytes,
        filename: filename,
        type: DocumentType.dbsCertificate,
      );

  /// Uploads any of the documents-checklist types. dbs_certificate keeps its
  /// original `dbs-documents/{uid}/` path (backward compatibility with
  /// existing rules/uploads); every other type lives under
  /// `personal-documents/{uid}/{type}/`, mirroring backend/documents.go's
  /// documentTypePrefix and storage.rules.
  /// Supports both [bytes] (safe on Flutter Web and Mobile) and [file].
  Future<void> uploadDocument({
    required String uid,
    File? file,
    Uint8List? bytes,
    required String filename,
    required DocumentType type,
  }) async {
    final typeStr = documentTypeToApiString(type);
    final path = type == DocumentType.dbsCertificate
        ? 'dbs-documents/$uid/$filename'
        : 'personal-documents/$uid/$typeStr/$filename';
    final ref = _storage.ref(path);
    // Storage rules require contentType to match `image/.*|application/pdf`
    final ext = filename.split('.').last.toLowerCase();
    final contentType = switch (ext) {
      'png' => 'image/png',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };
    final metadata = SettableMetadata(contentType: contentType);
    if (bytes != null) {
      await ref.putData(bytes, metadata);
    } else if (file != null) {
      await ref.putFile(file, metadata);
    } else {
      throw ArgumentError('Either bytes or file must be provided');
    }
    await _api.post(ApiFunction.createDocument, body: {
      'storagePath': path,
      'type': typeStr,
    });
  }

  /// Admin-only — the review queue (backend rejects with 403 NOT_ADMIN for
  /// non-admin callers regardless of what this returns).
  Future<List<PendingDocument>> listPendingDocuments() async {
    final res = await _api.post(ApiFunction.listPendingDocuments);
    final list = (res['documents'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return list.map(PendingDocument.fromJson).toList();
  }

  Future<void> reviewDocument({required String docId, required bool approve, String? note}) {
    return _api.post(ApiFunction.reviewDocument, body: {
      'docId': docId,
      'approve': approve,
      if (note != null) 'note': note,
    });
  }
}
