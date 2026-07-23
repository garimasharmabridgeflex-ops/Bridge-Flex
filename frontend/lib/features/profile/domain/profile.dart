enum UserRole { none, nursery, staff }

UserRole userRoleFromString(String? value) => switch (value) {
      'nursery' => UserRole.nursery,
      'staff' => UserRole.staff,
      _ => UserRole.none,
    };

enum DbsStatus { unverified, pending, verified }

DbsStatus dbsStatusFromString(String? value) => switch (value) {
      'pending' => DbsStatus.pending,
      'verified' => DbsStatus.verified,
      _ => DbsStatus.unverified,
    };

/// Fixed set, not free text, so it stays filterable/sortable later —
/// full app spec §1.2 step 2.
enum QualificationLevel { none, level2, level3, level4Plus }

QualificationLevel qualificationLevelFromString(String? value) => switch (value) {
      'level_2' => QualificationLevel.level2,
      'level_3' => QualificationLevel.level3,
      'level_4_plus' => QualificationLevel.level4Plus,
      _ => QualificationLevel.none,
    };

String qualificationLevelToApiString(QualificationLevel level) => switch (level) {
      QualificationLevel.level2 => 'level_2',
      QualificationLevel.level3 => 'level_3',
      QualificationLevel.level4Plus => 'level_4_plus',
      QualificationLevel.none => 'none',
    };

String qualificationLevelLabel(QualificationLevel level) => switch (level) {
      QualificationLevel.none => 'None yet',
      QualificationLevel.level2 => 'Level 2',
      QualificationLevel.level3 => 'Level 3',
      QualificationLevel.level4Plus => 'Level 4+',
    };

/// Self-reported by the nursery, never verified by Bridge Flex —
/// full app spec §1.3 step 2.
enum OfstedRating { notRated, requiresImprovement, good, outstanding, inadequate }

OfstedRating ofstedRatingFromString(String? value) => switch (value) {
      'outstanding' => OfstedRating.outstanding,
      'good' => OfstedRating.good,
      'requires_improvement' => OfstedRating.requiresImprovement,
      'inadequate' => OfstedRating.inadequate,
      _ => OfstedRating.notRated,
    };

String ofstedRatingToApiString(OfstedRating rating) => switch (rating) {
      OfstedRating.outstanding => 'outstanding',
      OfstedRating.good => 'good',
      OfstedRating.requiresImprovement => 'requires_improvement',
      OfstedRating.inadequate => 'inadequate',
      OfstedRating.notRated => 'not_rated',
    };

String ofstedRatingLabel(OfstedRating rating) => switch (rating) {
      OfstedRating.outstanding => 'Outstanding',
      OfstedRating.good => 'Good',
      OfstedRating.requiresImprovement => 'Requires improvement',
      OfstedRating.inadequate => 'Inadequate',
      OfstedRating.notRated => 'Not yet rated',
    };

/// Fixed set so it stays filterable, same rationale as the enums above.
enum NurseryType {
  unspecified,
  private_,
  preschool,
  daycare,
  montessori,
  forestSchool,
  beforeAfterSchoolClub,
  other,
}

NurseryType nurseryTypeFromString(String? value) => switch (value) {
      'private' => NurseryType.private_,
      'preschool' => NurseryType.preschool,
      'daycare' => NurseryType.daycare,
      'montessori' => NurseryType.montessori,
      'forest_school' => NurseryType.forestSchool,
      'before_after_school_club' => NurseryType.beforeAfterSchoolClub,
      'other' => NurseryType.other,
      _ => NurseryType.unspecified,
    };

String nurseryTypeToApiString(NurseryType type) => switch (type) {
      NurseryType.private_ => 'private',
      NurseryType.preschool => 'preschool',
      NurseryType.daycare => 'daycare',
      NurseryType.montessori => 'montessori',
      NurseryType.forestSchool => 'forest_school',
      NurseryType.beforeAfterSchoolClub => 'before_after_school_club',
      NurseryType.other => 'other',
      NurseryType.unspecified => '',
    };

String nurseryTypeLabel(NurseryType type) => switch (type) {
      NurseryType.private_ => 'Private nursery',
      NurseryType.preschool => 'Preschool',
      NurseryType.daycare => 'Daycare',
      NurseryType.montessori => 'Montessori',
      NurseryType.forestSchool => 'Forest school',
      NurseryType.beforeAfterSchoolClub => 'Before/after school club',
      NurseryType.other => 'Other',
      NurseryType.unspecified => 'Not specified',
    };

const List<NurseryType> nurseryTypeOptions = [
  NurseryType.private_,
  NurseryType.preschool,
  NurseryType.daycare,
  NurseryType.montessori,
  NurseryType.forestSchool,
  NurseryType.beforeAfterSchoolClub,
  NurseryType.other,
];

class PreviousRole {
  const PreviousRole({required this.settingName, required this.roleTitle, required this.duration});

  final String settingName;
  final String roleTitle;
  final String duration;

  factory PreviousRole.fromJson(Map<String, dynamic> json) => PreviousRole(
        settingName: json['settingName'] as String? ?? '',
        roleTitle: json['roleTitle'] as String? ?? '',
        duration: json['duration'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'settingName': settingName,
        'roleTitle': roleTitle,
        'duration': duration,
      };
}

class RatingSummary {
  const RatingSummary({required this.average, required this.count});
  final double average;
  final int count;

  factory RatingSummary.fromJson(Map<String, dynamic>? json) => RatingSummary(
        average: (json?['average'] as num?)?.toDouble() ?? 0,
        count: (json?['count'] as num?)?.toInt() ?? 0,
      );

  static const zero = RatingSummary(average: 0, count: 0);
}

/// Per-category rating averages — full app spec profile ratings-breakdown
/// request (communication/punctuality/professionalism/reliability/child
/// engagement). Computed server-side on read, not stored client-side.
class RatingBreakdown {
  const RatingBreakdown({
    required this.communication,
    required this.punctuality,
    required this.professionalism,
    required this.reliability,
    required this.childEngagement,
    required this.count,
  });

  final double communication;
  final double punctuality;
  final double professionalism;
  final double reliability;
  final double childEngagement;
  final int count;

  bool get hasData => count > 0;

  factory RatingBreakdown.fromJson(Map<String, dynamic>? json) => RatingBreakdown(
        communication: (json?['communication'] as num?)?.toDouble() ?? 0,
        punctuality: (json?['punctuality'] as num?)?.toDouble() ?? 0,
        professionalism: (json?['professionalism'] as num?)?.toDouble() ?? 0,
        reliability: (json?['reliability'] as num?)?.toDouble() ?? 0,
        childEngagement: (json?['childEngagement'] as num?)?.toDouble() ?? 0,
        count: (json?['count'] as num?)?.toInt() ?? 0,
      );
}

/// Nursery performance statistics — full app spec profile-fields request
/// ("completed shifts, repeat staff percentage, average response time,
/// cancellation rate, no show rate"). Computed server-side on read.
class NurseryStats {
  const NurseryStats({
    required this.completedShifts,
    required this.repeatStaffPercentage,
    required this.averageResponseTimeMinutes,
    required this.cancellationRate,
    required this.noShowRate,
  });

  final int completedShifts;
  final double repeatStaffPercentage;
  final double averageResponseTimeMinutes;
  final double cancellationRate;
  final double noShowRate;

  factory NurseryStats.fromJson(Map<String, dynamic>? json) => NurseryStats(
        completedShifts: (json?['completedShifts'] as num?)?.toInt() ?? 0,
        repeatStaffPercentage: (json?['repeatStaffPercentage'] as num?)?.toDouble() ?? 0,
        averageResponseTimeMinutes: (json?['averageResponseTimeMinutes'] as num?)?.toDouble() ?? 0,
        cancellationRate: (json?['cancellationRate'] as num?)?.toDouble() ?? 0,
        noShowRate: (json?['noShowRate'] as num?)?.toDouble() ?? 0,
      );
}

/// The caller's own private profiles/{uid} doc.
class Profile {
  const Profile({
    required this.role,
    required this.name,
    required this.description,
    required this.dbsStatus,
    required this.rating,
    this.lat,
    this.lng,
    this.phone = '',
    this.photoUrl = '',
    this.yearsExperience = 0,
    this.qualificationLevel = QualificationLevel.none,
    this.bio = '',
    this.previousRoles = const [],
    this.address = '',
    this.openingHours = '',
    this.ofstedRating = OfstedRating.notRated,
    this.photos = const [],
    this.age,
    this.city = '',
    this.travelDistanceMiles = 0,
    this.languages = const [],
    this.professionalSummary = '',
    this.qualifications = const [],
    this.skills = const [],
    this.availabilityDays = const [],
    this.availabilityShifts = const [],
    this.dbsCertificateNumber = '',
    this.dbsExpiryDate,
    this.nationality = '',
    this.visaStatus = '',
    this.rightToWorkStatus = '',
    this.rightToWorkVerified = false,
    this.logoUrl = '',
    this.registeredCompanyName = '',
    this.ofstedRegNumber = '',
    this.yearEstablished = 0,
    this.nurseryType = NurseryType.unspecified,
    this.website = '',
    this.postcode = '',
    this.email = '',
    this.shortDescription = '',
    this.facilities = const [],
    this.identityVerified = false,
    this.ofstedVerified = false,
    this.suspended = false,
    this.stats,
    this.ratingBreakdown,
  });

  final UserRole role;
  final String name;
  final String description;
  final DbsStatus dbsStatus;
  final RatingSummary rating;
  final double? lat;
  final double? lng;
  final String phone;
  final String photoUrl;

  // Staff wizard fields.
  final int yearsExperience;
  final QualificationLevel qualificationLevel;
  final String bio;
  final List<PreviousRole> previousRoles;
  final int? age;
  final String city;
  final int travelDistanceMiles;
  final List<String> languages;
  final String professionalSummary;
  final List<String> qualifications;
  final List<String> skills;
  final List<String> availabilityDays;
  final List<String> availabilityShifts;
  final String dbsCertificateNumber;
  final DateTime? dbsExpiryDate;
  final String nationality;
  final String visaStatus;
  final String rightToWorkStatus;
  final bool rightToWorkVerified;

  // Nursery wizard fields.
  final String address;
  final String openingHours;
  final OfstedRating ofstedRating;
  final List<String> photos;
  final String logoUrl;
  final String registeredCompanyName;
  final String ofstedRegNumber;
  final int yearEstablished;
  final NurseryType nurseryType;
  final String website;
  final String postcode;
  final String email;
  final String shortDescription;
  final List<String> facilities;
  final bool identityVerified;
  final bool ofstedVerified;

  // Admin-only (backend/services/core/function/admin.go setUserSuspended) —
  // only ever present on the admin user-detail fetch of someone else's
  // Profile; never client-writable via updateProfile.
  final bool suspended;

  // Computed, server-derived (not stored) — present only when returned by
  // getProfile/getPublicProfile.
  final NurseryStats? stats;
  final RatingBreakdown? ratingBreakdown;

  /// The one hard gate before landing in the app — full app spec §1.4:
  /// "Basics" complete. Everything else (experience, DBS, photos) can be
  /// finished later via the persistent banner instead of blocking entry.
  bool get hasCompletedBasics => switch (role) {
        UserRole.staff => name.trim().isNotEmpty && phone.trim().isNotEmpty,
        UserRole.nursery =>
          name.trim().isNotEmpty && phone.trim().isNotEmpty && address.trim().isNotEmpty,
        UserRole.none => false,
      };

  /// Drives the persistent "finish your profile" banner (full app spec
  /// §1.4) — true once Basics is done but optional wizard steps aren't.
  bool get hasIncompleteOptionalSteps {
    if (!hasCompletedBasics) return false;
    return switch (role) {
      UserRole.staff => dbsStatus == DbsStatus.unverified && bio.trim().isEmpty,
      UserRole.nursery => description.trim().isEmpty,
      UserRole.none => false,
    };
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        role: userRoleFromString(json['role'] as String?),
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        dbsStatus: dbsStatusFromString(json['dbsStatus'] as String?),
        rating: RatingSummary.fromJson(json['rating'] as Map<String, dynamic>?),
        lat: (json['location'] as Map<String, dynamic>?)?['latitude'] as double?,
        lng: (json['location'] as Map<String, dynamic>?)?['longitude'] as double?,
        phone: json['phone'] as String? ?? '',
        photoUrl: json['photoUrl'] as String? ?? '',
        yearsExperience: (json['yearsExperience'] as num?)?.toInt() ?? 0,
        qualificationLevel: qualificationLevelFromString(json['qualificationLevel'] as String?),
        bio: json['bio'] as String? ?? '',
        previousRoles: (json['previousRoles'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(PreviousRole.fromJson)
                .toList() ??
            const [],
        address: json['address'] as String? ?? '',
        openingHours: json['openingHours'] as String? ?? '',
        ofstedRating: ofstedRatingFromString(json['ofstedRating'] as String?),
        photos: (json['photos'] as List?)?.cast<String>() ?? const [],
        age: (json['age'] as num?)?.toInt(),
        city: json['city'] as String? ?? '',
        travelDistanceMiles: (json['travelDistanceMiles'] as num?)?.toInt() ?? 0,
        languages: (json['languages'] as List?)?.cast<String>() ?? const [],
        professionalSummary: json['professionalSummary'] as String? ?? '',
        qualifications: (json['qualifications'] as List?)?.cast<String>() ?? const [],
        skills: (json['skills'] as List?)?.cast<String>() ?? const [],
        availabilityDays: (json['availabilityDays'] as List?)?.cast<String>() ?? const [],
        availabilityShifts: (json['availabilityShifts'] as List?)?.cast<String>() ?? const [],
        dbsCertificateNumber: json['dbsCertificateNumber'] as String? ?? '',
        dbsExpiryDate:
            json['dbsExpiryDate'] != null ? DateTime.tryParse(json['dbsExpiryDate'] as String) : null,
        nationality: json['nationality'] as String? ?? '',
        visaStatus: json['visaStatus'] as String? ?? '',
        rightToWorkStatus: json['rightToWorkStatus'] as String? ?? '',
        rightToWorkVerified: json['rightToWorkVerified'] as bool? ?? false,
        logoUrl: json['logoUrl'] as String? ?? '',
        registeredCompanyName: json['registeredCompanyName'] as String? ?? '',
        ofstedRegNumber: json['ofstedRegNumber'] as String? ?? '',
        yearEstablished: (json['yearEstablished'] as num?)?.toInt() ?? 0,
        nurseryType: nurseryTypeFromString(json['nurseryType'] as String?),
        website: json['website'] as String? ?? '',
        postcode: json['postcode'] as String? ?? '',
        email: json['email'] as String? ?? '',
        shortDescription: json['shortDescription'] as String? ?? '',
        facilities: (json['facilities'] as List?)?.cast<String>() ?? const [],
        identityVerified: json['identityVerified'] as bool? ?? false,
        ofstedVerified: json['ofstedVerified'] as bool? ?? false,
        suspended: json['suspended'] as bool? ?? false,
        stats: json['stats'] != null ? NurseryStats.fromJson(json['stats'] as Map<String, dynamic>) : null,
        ratingBreakdown: json['ratingBreakdown'] != null
            ? RatingBreakdown.fromJson(json['ratingBreakdown'] as Map<String, dynamic>)
            : null,
      );
}

/// Any user's public profilesPublic/{uid} doc.
class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.role,
    required this.name,
    required this.locationArea,
    required this.rating,
    required this.dbsBadge,
    this.photoUrl = '',
    this.yearsExperience = 0,
    this.qualificationLevel = QualificationLevel.none,
    this.bio = '',
    this.previousRoles = const [],
    this.description = '',
    this.openingHours = '',
    this.ofstedRating = OfstedRating.notRated,
    this.photos = const [],
    this.age,
    this.city = '',
    this.travelDistanceMiles = 0,
    this.languages = const [],
    this.professionalSummary = '',
    this.qualifications = const [],
    this.skills = const [],
    this.availabilityDays = const [],
    this.availabilityShifts = const [],
    this.dbsExpiryDate,
    this.nationality = '',
    this.visaStatus = '',
    this.rightToWorkStatus = '',
    this.rightToWorkVerified = false,
    this.logoUrl = '',
    this.registeredCompanyName = '',
    this.ofstedRegNumber = '',
    this.yearEstablished = 0,
    this.nurseryType = NurseryType.unspecified,
    this.website = '',
    this.postcode = '',
    this.phone = '',
    this.email = '',
    this.shortDescription = '',
    this.facilities = const [],
    this.identityVerified = false,
    this.ofstedVerified = false,
    this.stats,
    this.ratingBreakdown,
  });

  final String uid;
  final UserRole role;
  final String name;
  final String locationArea;
  final RatingSummary rating;
  final DbsStatus dbsBadge;
  final String photoUrl;

  final int yearsExperience;
  final QualificationLevel qualificationLevel;
  final String bio;
  final List<PreviousRole> previousRoles;
  final int? age;
  final String city;
  final int travelDistanceMiles;
  final List<String> languages;
  final String professionalSummary;
  final List<String> qualifications;
  final List<String> skills;
  final List<String> availabilityDays;
  final List<String> availabilityShifts;
  final DateTime? dbsExpiryDate;
  final String nationality;
  final String visaStatus;
  final String rightToWorkStatus;
  final bool rightToWorkVerified;

  final String description;
  final String openingHours;
  final OfstedRating ofstedRating;
  final List<String> photos;
  final String logoUrl;
  final String registeredCompanyName;
  final String ofstedRegNumber;
  final int yearEstablished;
  final NurseryType nurseryType;
  final String website;
  final String postcode;
  final String phone;
  final String email;
  final String shortDescription;
  final List<String> facilities;
  final bool identityVerified;
  final bool ofstedVerified;

  final NurseryStats? stats;
  final RatingBreakdown? ratingBreakdown;

  factory PublicProfile.fromJson(String uid, Map<String, dynamic> json) => PublicProfile(
        uid: uid,
        role: userRoleFromString(json['role'] as String?),
        name: json['name'] as String? ?? '',
        locationArea: json['locationArea'] as String? ?? '',
        rating: RatingSummary.fromJson(json['rating'] as Map<String, dynamic>?),
        dbsBadge: dbsStatusFromString(json['dbsBadge'] as String?),
        photoUrl: json['photoUrl'] as String? ?? '',
        yearsExperience: (json['yearsExperience'] as num?)?.toInt() ?? 0,
        qualificationLevel: qualificationLevelFromString(json['qualificationLevel'] as String?),
        bio: json['bio'] as String? ?? '',
        previousRoles: (json['previousRoles'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(PreviousRole.fromJson)
                .toList() ??
            const [],
        description: json['description'] as String? ?? '',
        openingHours: json['openingHours'] as String? ?? '',
        ofstedRating: ofstedRatingFromString(json['ofstedRating'] as String?),
        photos: (json['photos'] as List?)?.cast<String>() ?? const [],
        age: (json['age'] as num?)?.toInt(),
        city: json['city'] as String? ?? '',
        travelDistanceMiles: (json['travelDistanceMiles'] as num?)?.toInt() ?? 0,
        languages: (json['languages'] as List?)?.cast<String>() ?? const [],
        professionalSummary: json['professionalSummary'] as String? ?? '',
        qualifications: (json['qualifications'] as List?)?.cast<String>() ?? const [],
        skills: (json['skills'] as List?)?.cast<String>() ?? const [],
        availabilityDays: (json['availabilityDays'] as List?)?.cast<String>() ?? const [],
        availabilityShifts: (json['availabilityShifts'] as List?)?.cast<String>() ?? const [],
        dbsExpiryDate:
            json['dbsExpiryDate'] != null ? DateTime.tryParse(json['dbsExpiryDate'] as String) : null,
        nationality: json['nationality'] as String? ?? '',
        visaStatus: json['visaStatus'] as String? ?? '',
        rightToWorkStatus: json['rightToWorkStatus'] as String? ?? '',
        rightToWorkVerified: json['rightToWorkVerified'] as bool? ?? false,
        logoUrl: json['logoUrl'] as String? ?? '',
        registeredCompanyName: json['registeredCompanyName'] as String? ?? '',
        ofstedRegNumber: json['ofstedRegNumber'] as String? ?? '',
        yearEstablished: (json['yearEstablished'] as num?)?.toInt() ?? 0,
        nurseryType: nurseryTypeFromString(json['nurseryType'] as String?),
        website: json['website'] as String? ?? '',
        postcode: json['postcode'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        shortDescription: json['shortDescription'] as String? ?? '',
        facilities: (json['facilities'] as List?)?.cast<String>() ?? const [],
        identityVerified: json['identityVerified'] as bool? ?? false,
        ofstedVerified: json['ofstedVerified'] as bool? ?? false,
        stats: json['stats'] != null ? NurseryStats.fromJson(json['stats'] as Map<String, dynamic>) : null,
        ratingBreakdown: json['ratingBreakdown'] != null
            ? RatingBreakdown.fromJson(json['ratingBreakdown'] as Map<String, dynamic>)
            : null,
      );
}

/// Lets the "my profile" screen reuse [NurseryDetails]/[StaffDetails] (built
/// for viewing someone *else's* profile) to render your own — rather than
/// duplicating that entire detail layout, since the two field sets are
/// otherwise identical. `locationArea` has no equivalent on the private
/// [Profile] (it's a server-derived geohash prefix only present on
/// profilesPublic), so it's left blank; every other field maps directly.
extension ProfileToPublicView on Profile {
  PublicProfile toPublicView(String uid) => PublicProfile(
        uid: uid,
        role: role,
        name: name,
        locationArea: '',
        rating: rating,
        dbsBadge: dbsStatus,
        photoUrl: photoUrl,
        yearsExperience: yearsExperience,
        qualificationLevel: qualificationLevel,
        bio: bio,
        previousRoles: previousRoles,
        description: description,
        openingHours: openingHours,
        ofstedRating: ofstedRating,
        photos: photos,
        age: age,
        city: city,
        travelDistanceMiles: travelDistanceMiles,
        languages: languages,
        professionalSummary: professionalSummary,
        qualifications: qualifications,
        skills: skills,
        availabilityDays: availabilityDays,
        availabilityShifts: availabilityShifts,
        dbsExpiryDate: dbsExpiryDate,
        nationality: nationality,
        visaStatus: visaStatus,
        rightToWorkStatus: rightToWorkStatus,
        rightToWorkVerified: rightToWorkVerified,
        logoUrl: logoUrl,
        registeredCompanyName: registeredCompanyName,
        ofstedRegNumber: ofstedRegNumber,
        yearEstablished: yearEstablished,
        nurseryType: nurseryType,
        website: website,
        postcode: postcode,
        phone: phone,
        email: email,
        shortDescription: shortDescription,
        facilities: facilities,
        identityVerified: identityVerified,
        ofstedVerified: ofstedVerified,
        stats: stats,
        ratingBreakdown: ratingBreakdown,
      );
}
