import '../../documents/domain/document_status.dart';
import '../../profile/domain/profile.dart';

/// Platform-wide snapshot — backend/services/core/function/admin.go
/// getPlatformStats. Full app spec admin-page request: "a dashboard that
/// shows platform wide metrics and statistics".
class PlatformStats {
  const PlatformStats({
    required this.totalNurseries,
    required this.totalStaff,
    required this.suspendedUsers,
    required this.pendingDbs,
    required this.totalShifts,
    required this.openShifts,
    required this.bookedShifts,
    required this.completedShifts,
    required this.cancelledShifts,
    required this.pendingDocuments,
    required this.totalRatings,
  });

  final int totalNurseries;
  final int totalStaff;
  final int suspendedUsers;
  final int pendingDbs;
  final int totalShifts;
  final int openShifts;
  final int bookedShifts;
  final int completedShifts;
  final int cancelledShifts;
  final int pendingDocuments;
  final int totalRatings;

  factory PlatformStats.fromJson(Map<String, dynamic> json) => PlatformStats(
        totalNurseries: (json['totalNurseries'] as num?)?.toInt() ?? 0,
        totalStaff: (json['totalStaff'] as num?)?.toInt() ?? 0,
        suspendedUsers: (json['suspendedUsers'] as num?)?.toInt() ?? 0,
        pendingDbs: (json['pendingDbs'] as num?)?.toInt() ?? 0,
        totalShifts: (json['totalShifts'] as num?)?.toInt() ?? 0,
        openShifts: (json['openShifts'] as num?)?.toInt() ?? 0,
        bookedShifts: (json['bookedShifts'] as num?)?.toInt() ?? 0,
        completedShifts: (json['completedShifts'] as num?)?.toInt() ?? 0,
        cancelledShifts: (json['cancelledShifts'] as num?)?.toInt() ?? 0,
        pendingDocuments: (json['pendingDocuments'] as num?)?.toInt() ?? 0,
        totalRatings: (json['totalRatings'] as num?)?.toInt() ?? 0,
      );
}

/// One row in the admin user-management list —
/// backend/services/core/function/admin.go listAllUsers.
class AdminUserSummary {
  const AdminUserSummary({
    required this.uid,
    required this.role,
    required this.name,
    required this.phone,
    required this.email,
    required this.dbsStatus,
    required this.suspended,
    required this.identityVerified,
    required this.ofstedVerified,
    required this.ratingAverage,
    required this.ratingCount,
  });

  final String uid;
  final UserRole role;
  final String name;
  final String phone;
  final String email;
  final DbsStatus dbsStatus;
  final bool suspended;
  final bool identityVerified;
  final bool ofstedVerified;
  final double ratingAverage;
  final int ratingCount;

  factory AdminUserSummary.fromJson(Map<String, dynamic> json) => AdminUserSummary(
        uid: json['uid'] as String? ?? '',
        role: userRoleFromString(json['role'] as String?),
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        dbsStatus: dbsStatusFromString(json['dbsStatus'] as String?),
        suspended: json['suspended'] as bool? ?? false,
        identityVerified: json['identityVerified'] as bool? ?? false,
        ofstedVerified: json['ofstedVerified'] as bool? ?? false,
        ratingAverage: ((json['rating'] as Map<String, dynamic>?)?['average'] as num?)?.toDouble() ?? 0,
        ratingCount: ((json['rating'] as Map<String, dynamic>?)?['count'] as num?)?.toInt() ?? 0,
      );
}

/// One document entry in an admin user-detail view — every document that
/// user has ever uploaded, not just the latest-per-type
/// (backend/services/core/function/admin.go getUserDetail).
class AdminDocumentEntry {
  const AdminDocumentEntry({
    required this.docId,
    required this.type,
    required this.status,
    required this.storagePath,
    required this.reviewNote,
    required this.uploadedAt,
  });

  final String docId;
  final DocumentType type;
  final DocReviewStatus status;
  final String storagePath;
  final String reviewNote;
  final DateTime? uploadedAt;

  factory AdminDocumentEntry.fromJson(Map<String, dynamic> json) => AdminDocumentEntry(
        docId: json['docId'] as String? ?? '',
        type: documentTypeFromString(json['type'] as String?),
        status: docReviewStatusFromString(json['status'] as String? ?? 'none'),
        storagePath: json['storagePath'] as String? ?? '',
        reviewNote: json['reviewNote'] as String? ?? '',
        uploadedAt: json['uploadedAt'] != null
            ? DateTime.tryParse(json['uploadedAt'] as String)?.toLocal()
            : null,
      );
}

/// The full admin view of one user — backend/services/core/function/admin.go
/// getUserDetail. Reuses [Profile.fromJson] since the backend returns the
/// exact same shape getProfile does (computed stats/ratingBreakdown included).
class AdminUserDetail {
  const AdminUserDetail({required this.uid, required this.profile, required this.documents});

  final String uid;
  final Profile profile;
  final List<AdminDocumentEntry> documents;

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) => AdminUserDetail(
        uid: json['uid'] as String? ?? '',
        profile: Profile.fromJson(json['profile'] as Map<String, dynamic>? ?? const {}),
        documents: (json['documents'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(AdminDocumentEntry.fromJson)
                .toList() ??
            const [],
      );
}
