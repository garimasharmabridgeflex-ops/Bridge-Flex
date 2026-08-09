import 'package:cloud_firestore/cloud_firestore.dart';

enum ShiftStatus { open, booked, cancelled }

ShiftStatus shiftStatusFromString(String value) => switch (value) {
      'open' => ShiftStatus.open,
      'booked' => ShiftStatus.booked,
      'cancelled' => ShiftStatus.cancelled,
      _ => ShiftStatus.open,
    };

enum PaymentStatus { notRequired, pending, paid }

PaymentStatus paymentStatusFromString(String value) => switch (value) {
      'pending' => PaymentStatus.pending,
      'paid' => PaymentStatus.paid,
      _ => PaymentStatus.notRequired,
    };

class Shift {
  const Shift({
    required this.id,
    required this.nurseryId,
    required this.title,
    this.description = '',
    this.capacity = 1,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.payRate,
    required this.status,
    required this.bookedStaffId,
    this.bookedStaffIds = const [],
    required this.paymentStatus,
    required this.createdAt,
    this.nurseryName,
    this.ageGroup = '',
    this.room = '',
    this.numberOfChildren = 0,
    this.expectedDuties = const [],
    this.requirements = const [],
    this.noShowStaffIds = const [],
    this.pendingStaffIds = const [],
    this.rejectedStaffIds = const [],
  });

  final String id;
  final String nurseryId;
  final String title;
  final String description;
  final int capacity;
  final String date;
  final DateTime startTime;
  final DateTime endTime;
  final double payRate;
  final ShiftStatus status;

  /// "Most recent acceptor" — kept for backward compatibility. Use
  /// [bookedStaffIds] for membership checks (capacity/multi-staff aware).
  final String? bookedStaffId;
  final List<String> bookedStaffIds;

  final PaymentStatus paymentStatus;
  final DateTime createdAt;

  /// Denormalized client-side by joining profilesPublic; not part of the
  /// shifts doc itself.
  final String? nurseryName;

  final String ageGroup;
  final String room;
  final int numberOfChildren;
  final List<String> expectedDuties;
  final List<String> requirements;
  final List<String> noShowStaffIds;

  /// Applicants awaiting the nursery's decision. These do NOT consume
  /// capacity: the shift stays open and visible to other staff until enough
  /// applicants have been approved.
  final List<String> pendingStaffIds;

  /// Applicants the nursery declined, or who were cleared automatically when
  /// the shift filled up.
  final List<String> rejectedStaffIds;

  Duration get duration => endTime.difference(startTime);

  double get totalPay => duration.inMinutes / 60 * payRate;

  int get spotsFilled => bookedStaffIds.length;

  int get spotsRemaining => (capacity - spotsFilled).clamp(0, capacity);

  bool isBookedBy(String uid) => bookedStaffIds.contains(uid);

  bool isMarkedNoShow(String uid) => noShowStaffIds.contains(uid);

  bool hasAppliedBy(String uid) => pendingStaffIds.contains(uid);

  bool wasRejectedFor(String uid) => rejectedStaffIds.contains(uid);

  /// True when this user has no further action available on the shift: they
  /// are booked, waiting on a decision, or have already been declined.
  bool hasDecidedOrPending(String uid) =>
      isBookedBy(uid) || hasAppliedBy(uid) || wasRejectedFor(uid);

  int get applicantCount => pendingStaffIds.length;

  /// Parses the JSON shape returned by ListOpenShifts/ListMyShifts/GetShift:
  /// `{"shiftId": "...", "shift": {...}}` (or just the inner map for
  /// GetShift, which returns the Shift object directly — callers pass id
  /// separately in that case).
  factory Shift.fromJson(String id, Map<String, dynamic> json) {
    return Shift(
      id: id,
      nurseryId: json['nurseryId'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      capacity: (json['capacity'] as num?)?.toInt() ?? 1,
      date: json['date'] as String,
      startTime: DateTime.parse(json['startTime'] as String).toLocal(),
      endTime: DateTime.parse(json['endTime'] as String).toLocal(),
      payRate: (json['payRate'] as num).toDouble(),
      status: shiftStatusFromString(json['status'] as String? ?? 'open'),
      bookedStaffId: json['bookedStaffId'] as String?,
      bookedStaffIds: (json['bookedStaffIds'] as List?)?.cast<String>() ??
          (json['bookedStaffId'] != null ? [json['bookedStaffId'] as String] : const []),
      paymentStatus:
          paymentStatusFromString(json['paymentStatus'] as String? ?? 'not_required'),
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      ageGroup: json['ageGroup'] as String? ?? '',
      room: json['room'] as String? ?? '',
      numberOfChildren: (json['numberOfChildren'] as num?)?.toInt() ?? 0,
      expectedDuties: (json['expectedDuties'] as List?)?.cast<String>() ?? const [],
      requirements: (json['requirements'] as List?)?.cast<String>() ?? const [],
      noShowStaffIds: (json['noShowStaffIds'] as List?)?.cast<String>() ?? const [],
      pendingStaffIds: (json['pendingStaffIds'] as List?)?.cast<String>() ?? const [],
      rejectedStaffIds: (json['rejectedStaffIds'] as List?)?.cast<String>() ?? const [],
    );
  }

  factory Shift.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Shift(
      id: doc.id,
      nurseryId: data['nurseryId'] as String,
      title: data['title'] as String,
      description: data['description'] as String? ?? '',
      capacity: (data['capacity'] as num?)?.toInt() ?? 1,
      date: data['date'] as String,
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      payRate: (data['payRate'] as num).toDouble(),
      status: shiftStatusFromString(data['status'] as String? ?? 'open'),
      bookedStaffId: data['bookedStaffId'] as String?,
      bookedStaffIds: (data['bookedStaffIds'] as List?)?.cast<String>() ??
          (data['bookedStaffId'] != null ? [data['bookedStaffId'] as String] : const []),
      paymentStatus:
          paymentStatusFromString(data['paymentStatus'] as String? ?? 'not_required'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ageGroup: data['ageGroup'] as String? ?? '',
      room: data['room'] as String? ?? '',
      numberOfChildren: (data['numberOfChildren'] as num?)?.toInt() ?? 0,
      expectedDuties: (data['expectedDuties'] as List?)?.cast<String>() ?? const [],
      requirements: (data['requirements'] as List?)?.cast<String>() ?? const [],
      noShowStaffIds: (data['noShowStaffIds'] as List?)?.cast<String>() ?? const [],
      pendingStaffIds: (data['pendingStaffIds'] as List?)?.cast<String>() ?? const [],
      rejectedStaffIds: (data['rejectedStaffIds'] as List?)?.cast<String>() ?? const [],
    );
  }

  Shift copyWith({String? nurseryName}) => Shift(
        id: id,
        nurseryId: nurseryId,
        title: title,
        description: description,
        capacity: capacity,
        date: date,
        startTime: startTime,
        endTime: endTime,
        payRate: payRate,
        status: status,
        bookedStaffId: bookedStaffId,
        bookedStaffIds: bookedStaffIds,
        paymentStatus: paymentStatus,
        createdAt: createdAt,
        nurseryName: nurseryName ?? this.nurseryName,
        ageGroup: ageGroup,
        room: room,
        numberOfChildren: numberOfChildren,
        expectedDuties: expectedDuties,
        requirements: requirements,
        noShowStaffIds: noShowStaffIds,
        pendingStaffIds: pendingStaffIds,
        rejectedStaffIds: rejectedStaffIds,
      );
}
