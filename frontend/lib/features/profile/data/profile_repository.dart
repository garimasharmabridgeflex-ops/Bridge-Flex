import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/config/env.dart';
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
  }) {
    return _api.post(ApiFunction.updateProfile, body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
      if (phone != null) 'phone': phone,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (yearsExperience != null) 'yearsExperience': yearsExperience,
      if (qualificationLevel != null)
        'qualificationLevel': qualificationLevelToApiString(qualificationLevel),
      if (bio != null) 'bio': bio,
      if (previousRoles != null)
        'previousRoles': previousRoles.map((r) => r.toJson()).toList(),
      if (address != null) 'address': address,
      if (openingHours != null) 'openingHours': openingHours,
      if (ofstedRating != null) 'ofstedRating': ofstedRatingToApiString(ofstedRating),
      if (photos != null) 'photos': photos,
      if (age != null) 'age': age,
      if (city != null) 'city': city,
      if (travelDistanceMiles != null) 'travelDistanceMiles': travelDistanceMiles,
      if (languages != null) 'languages': languages,
      if (professionalSummary != null) 'professionalSummary': professionalSummary,
      if (qualifications != null) 'qualifications': qualifications,
      if (skills != null) 'skills': skills,
      if (availabilityDays != null) 'availabilityDays': availabilityDays,
      if (availabilityShifts != null) 'availabilityShifts': availabilityShifts,
      if (dbsCertificateNumber != null) 'dbsCertificateNumber': dbsCertificateNumber,
      if (dbsExpiryDate != null) 'dbsExpiryDate': dbsExpiryDate.toUtc().toIso8601String(),
      if (nationality != null) 'nationality': nationality,
      if (visaStatus != null) 'visaStatus': visaStatus,
      if (rightToWorkStatus != null) 'rightToWorkStatus': rightToWorkStatus,
      if (logoUrl != null) 'logoUrl': logoUrl,
      if (registeredCompanyName != null) 'registeredCompanyName': registeredCompanyName,
      if (ofstedRegNumber != null) 'ofstedRegNumber': ofstedRegNumber,
      if (yearEstablished != null) 'yearEstablished': yearEstablished,
      if (nurseryType != null) 'nurseryType': nurseryTypeToApiString(nurseryType),
      if (website != null) 'website': website,
      if (postcode != null) 'postcode': postcode,
      if (email != null) 'email': email,
      if (shortDescription != null) 'shortDescription': shortDescription,
      if (facilities != null) 'facilities': facilities,
    });
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
}
