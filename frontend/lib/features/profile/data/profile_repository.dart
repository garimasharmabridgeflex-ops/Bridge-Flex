import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/config/env.dart';
import '../domain/branch.dart';
import '../domain/profile.dart';

class ProfileRepository {
  ProfileRepository(this._api, this._storage);

  final ApiClient _api;
  final FirebaseStorage _storage;

  /// Plain HTTP GetProfile rather than a live Firestore stream — see the
  /// note on shift_repository.dart's fetchOpenShifts for why. Callers that
  /// need fresh data after a mutation (setRole, updateProfile) re-fetch by
  /// invalidating the provider, since there's no push update anymore.
  Future<Profile?> fetchOwnProfile({String? fallbackUid, String? fallbackName}) async {
    try {
      final res = await _api.post(ApiFunction.getProfile);
      return Profile.fromJson(res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        if (fallbackUid != null) {
          return Profile(
            role: UserRole.none,
            name: fallbackName ?? '',
            description: '',
            dbsStatus: DbsStatus.unverified,
            rating: const RatingSummary(average: 0, count: 0),
          );
        }
        return null;
      }
      rethrow;
    }
  }

  Future<void> setRole(UserRole role) => _api.post(
        ApiFunction.updateProfile,
        body: {'role': role == UserRole.nursery ? 'nursery' : 'staff'},
      );

  Future<void> updateProfile({
    String? name,
    String? description,
    double? lat,
    double? lng,
    String? phone,
    String? photoUrl,
    int? yearsExperience,
    QualificationLevel? qualificationLevel,
    String? bio,
    List<PreviousRole>? previousRoles,
    String? address,
    String? openingHours,
    OfstedRating? ofstedRating,
    List<String>? photos,
    int? age,
    String? city,
    int? travelDistanceMiles,
    List<String>? languages,
    String? professionalSummary,
    List<String>? qualifications,
    List<String>? skills,
    List<String>? availabilityDays,
    List<String>? availabilityShifts,
    String? dbsCertificateNumber,
    DateTime? dbsExpiryDate,
    String? nationality,
    String? visaStatus,
    String? rightToWorkStatus,
    String? logoUrl,
    String? registeredCompanyName,
    String? ofstedRegNumber,
    int? yearEstablished,
    NurseryType? nurseryType,
    String? website,
    String? postcode,
    String? email,
    String? shortDescription,
    List<String>? facilities,
    String? companyNumber,
    String? billingAddress,
    String? billingEmail,
    String? billingContactPerson,
    String? preferredPaymentMethod,
    int? locationCount,
    String? staffingRequirements,
  }) {
    return _api.post(ApiFunction.updateProfile, body: {
      'name': ?name,
      'description': ?description,
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
      'phone': ?phone,
      'photoUrl': ?photoUrl,
      'yearsExperience': ?yearsExperience,
      if (qualificationLevel != null)
        'qualificationLevel': qualificationLevelToApiString(qualificationLevel),
      'bio': ?bio,
      if (previousRoles != null)
        'previousRoles': previousRoles.map((r) => r.toJson()).toList(),
      'address': ?address,
      'openingHours': ?openingHours,
      if (ofstedRating != null) 'ofstedRating': ofstedRatingToApiString(ofstedRating),
      'photos': ?photos,
      'age': ?age,
      'city': ?city,
      'travelDistanceMiles': ?travelDistanceMiles,
      'languages': ?languages,
      'professionalSummary': ?professionalSummary,
      'qualifications': ?qualifications,
      'skills': ?skills,
      'availabilityDays': ?availabilityDays,
      'availabilityShifts': ?availabilityShifts,
      'dbsCertificateNumber': ?dbsCertificateNumber,
      if (dbsExpiryDate != null) 'dbsExpiryDate': dbsExpiryDate.toUtc().toIso8601String(),
      'nationality': ?nationality,
      'visaStatus': ?visaStatus,
      'rightToWorkStatus': ?rightToWorkStatus,
      'logoUrl': ?logoUrl,
      'registeredCompanyName': ?registeredCompanyName,
      'ofstedRegNumber': ?ofstedRegNumber,
      'yearEstablished': ?yearEstablished,
      if (nurseryType != null && nurseryType != NurseryType.unspecified)
        'nurseryType': nurseryTypeToApiString(nurseryType),
      'website': ?website,
      'postcode': ?postcode,
      'email': ?email,
      'shortDescription': ?shortDescription,
      'facilities': ?facilities,
      'companyNumber': ?companyNumber,
      'billingAddress': ?billingAddress,
      'billingEmail': ?billingEmail,
      'billingContactPerson': ?billingContactPerson,
      'preferredPaymentMethod': ?preferredPaymentMethod,
      'locationCount': ?locationCount,
      'staffingRequirements': ?staffingRequirements,
    });
  }

  Future<List<Branch>> listBranches([String? nurseryId]) async {
    final query = nurseryId != null ? {'nurseryId': nurseryId} : <String, String>{};
    final res = await _api.postWithQuery(ApiFunction.listBranches, query: query);
    final list = res['branches'] as List<dynamic>? ?? [];
    return list.map((e) => Branch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> createBranch(Branch branch) async {
    final res = await _api.post(ApiFunction.createBranch, body: branch.toJson());
    return res['branchId'] as String? ?? '';
  }

  Future<void> updateBranch(Branch branch) async {
    await _api.post(ApiFunction.updateBranch, body: {
      'branchId': branch.id,
      ...branch.toJson(),
    });
  }

  Future<void> deleteBranch(String branchId) async {
    await _api.post(ApiFunction.deleteBranch, body: {'branchId': branchId});
  }

  /// Deletes the caller's own profile/documents server-side, then their
  /// Firebase Auth user — see backend/services/core/function/profiles.go's
  /// deleteAccount for exactly what does and doesn't get cleaned up.
  Future<void> deleteAccount() => _api.post(ApiFunction.deleteAccount);

  Future<PublicProfile?> fetchPublicProfile(String uid) async {
    try {
      final res = await _api.postWithQuery(ApiFunction.getPublicProfile, query: {'uid': uid});
      return PublicProfile.fromJson(uid, res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Uploads to `profile-photos/{uid}/photo.jpg` (any signed-in user may
  /// read — Storage rules — since this is shown on the public profile) and
  /// returns the download URL to store on the profile via updateProfile.
  Future<String> uploadProfilePhoto({required String uid, required File file}) async {
    final ref = _storage.ref('profile-photos/$uid/photo.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Web-safe profile photo upload from raw bytes.
  Future<String> uploadProfilePhotoBytes({required String uid, required Uint8List bytes}) async {
    final ref = _storage.ref('profile-photos/$uid/photo.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Uploads one nursery setting photo to `nursery-photos/{uid}/{n}.jpg`.
  /// Full app spec §1.3 caps this at ~4 photos — enforced by the caller
  /// (presentation layer), not here.
  Future<String> uploadNurseryPhoto({
    required String uid,
    required File file,
    required int index,
  }) async {
    final ref = _storage.ref('nursery-photos/$uid/$index.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Web-safe nursery photo upload from raw bytes.
  Future<String> uploadNurseryPhotoBytes({
    required String uid,
    required Uint8List bytes,
    required int index,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('nursery-photos/$uid/${index}_$timestamp.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
