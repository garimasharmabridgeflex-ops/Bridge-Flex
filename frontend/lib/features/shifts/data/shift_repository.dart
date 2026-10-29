import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/shift.dart';

class ShiftRepository {
  ShiftRepository(this._api, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _firestore;

  List<Shift> _parseShiftList(Map<String, dynamic> res) {
    final raw = (res['shifts'] as List?) ?? const [];
    return raw.cast<Map<String, dynamic>>().map((entry) {
      return Shift.fromJson(
        entry['shiftId'] as String,
        (entry['shift'] as Map).cast<String, dynamic>(),
      );
    }).toList();
  }

  /// Any signed-in user may read open shifts (§3). Plain HTTP rather than a
  /// live Firestore stream — see ShiftsRepository note in browse_shifts_screen.
  Future<List<Shift>> fetchOpenShifts() async {
    final res = await _api.post(ApiFunction.listOpenShifts);
    return _parseShiftList(res);
  }

  /// Nursery gets shifts it posted; staff get shifts booked to them —
  /// determined server-side from the caller's own profile role.
  Future<List<Shift>> fetchMyShifts() async {
    final res = await _api.post(ApiFunction.listMyShifts);
    return _parseShiftList(res);
  }

  /// Live stream of every open shift, mirroring listOpenShifts exactly
  /// (same status filter, same createdAt ordering). The rules already let any
  /// signed-in user read open shifts, and the composite index behind it is the
  /// same one the HTTP endpoint uses, so a shift posted a second ago appears
  /// here a second ago.
  Stream<List<Shift>> watchOpenShifts() {
    return _firestore
        .collection('shifts')
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Shift.fromFirestore).toList());
  }

  /// Live stream of the shifts a practitioner is attached to, mirroring the
  /// staff side of listMyShifts: legacy single-booker docs, multi-capacity
  /// bookedStaffIds, and shifts they've applied to but the nursery hasn't
  /// decided on yet.
  ///
  /// Firestore has no client-side OR, so the three queries are merged into one
  /// deduplicated list here. Each query's snapshot is kept whole (a doc that
  /// drops out of one query but is still in another must not disappear), and
  /// results are sorted newest-first like the rest of the shift lists.
  Stream<List<Shift>> watchMyShiftsStaff(String uid) {
    final queries = <Query<Map<String, dynamic>>>[
      _firestore.collection('shifts').where('bookedStaffIds', arrayContains: uid),
      _firestore.collection('shifts').where('bookedStaffId', isEqualTo: uid),
      _firestore.collection('shifts').where('pendingStaffIds', arrayContains: uid),
    ];

    return Stream<List<Shift>>.multi((controller) {
      final perQuery = List.generate(queries.length, (_) => <String, Shift>{});
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emit() {
        final merged = <String, Shift>{};
        for (final part in perQuery) {
          merged.addAll(part);
        }
        final list = merged.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(list);
      }

      for (var i = 0; i < queries.length; i++) {
        subs.add(queries[i].snapshots().listen(
          (snap) {
            perQuery[i]
              ..clear()
              ..addAll({
                for (final doc in snap.docs) doc.id: Shift.fromFirestore(doc),
              });
            emit();
          },
          onError: controller.addError,
        ));
      }

      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    });
  }

  /// Live Firestore snapshot stream of a single shift doc.
  /// Eliminates the need for manual refreshes when applications, status
  /// changes, or cancellations occur.
  Stream<Shift?> watchShift(String shiftId) {
    return _firestore
        .collection('shifts')
        .doc(shiftId)
        .snapshots()
        .map((snap) {
          if (!snap.exists || snap.data() == null) return null;
          return Shift.fromFirestore(snap);
        });
  }

  /// Real-time stream of nursery's posted shifts for instant status & applicant updates.
  Stream<List<Shift>> watchMyShiftsNursery(String nurseryId) {
    return _firestore
        .collection('shifts')
        .where('nurseryId', isEqualTo: nurseryId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(Shift.fromFirestore).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Future<Shift?> fetchShift(String shiftId) async {
    final res = await _api.postWithQuery(ApiFunction.getShift, query: {'shiftId': shiftId});
    return Shift.fromJson(shiftId, res);
  }

  Future<String> createShift({
    required String title,
    String description = '',
    int capacity = 1,
    required String date,
    required DateTime startTime,
    required DateTime endTime,
    required double payRate,
    String ageGroup = '',
    String room = '',
    int numberOfChildren = 0,
    List<String> expectedDuties = const [],
    List<String> requirements = const [],
    String branchId = '',
    String requiredQualification = '',
    int unpaidBreakMinutes = 0,
    String safeguardingNotes = '',
    String healthAndSafetyNotes = '',
  }) async {
    final res = await _api.post(ApiFunction.createShift, body: {
      'title': title,
      'description': description,
      'capacity': capacity,
      'date': date,
      'startTime': startTime.toUtc().toIso8601String(),
      'endTime': endTime.toUtc().toIso8601String(),
      'payRate': payRate,
      'ageGroup': ageGroup,
      'room': room,
      'numberOfChildren': numberOfChildren,
      'expectedDuties': expectedDuties,
      'requirements': requirements,
      if (branchId.isNotEmpty) 'branchId': branchId,
      if (requiredQualification.isNotEmpty) 'requiredQualification': requiredQualification,
      if (unpaidBreakMinutes > 0) 'unpaidBreakMinutes': unpaidBreakMinutes,
      if (safeguardingNotes.isNotEmpty) 'safeguardingNotes': safeguardingNotes,
      if (healthAndSafetyNotes.isNotEmpty) 'healthAndSafetyNotes': healthAndSafetyNotes,
    });
    return res['shiftId'] as String;
  }

  Future<void> updateShift({
    required String shiftId,
    String? title,
    String? date,
    DateTime? startTime,
    DateTime? endTime,
    double? payRate,
    String? room,
    String? ageGroup,
    int? numberOfChildren,
    List<String>? expectedDuties,
    List<String>? requirements,
    String? description,
    int? unpaidBreakMinutes,
    String? requiredQualification,
  }) {
    return _api.post(ApiFunction.updateShift, body: {
      'shiftId': shiftId,
      if (title != null) 'title': title,
      if (date != null) 'date': date,
      if (startTime != null) 'startTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
      if (payRate != null) 'payRate': payRate,
      if (room != null) 'room': room,
      if (ageGroup != null) 'ageGroup': ageGroup,
      if (numberOfChildren != null) 'numberOfChildren': numberOfChildren,
      if (expectedDuties != null) 'expectedDuties': expectedDuties,
      if (requirements != null) 'requirements': requirements,
      if (description != null) 'description': description,
      if (unpaidBreakMinutes != null) 'unpaidBreakMinutes': unpaidBreakMinutes,
      if (requiredQualification != null) 'requiredQualification': requiredQualification,
    });
  }

  /// Applies for a shift. Despite the endpoint name this no longer books the
  /// shift outright — it registers an application the nursery then approves or
  /// declines, and the shift stays open to other staff in the meantime.
  Future<void> applyForShift(String shiftId) =>
      _api.post(ApiFunction.acceptShift, body: {'shiftId': shiftId});

  /// Nursery-only: confirms an applicant, consuming one of the shift's places.
  Future<void> approveApplicant({required String shiftId, required String staffId}) =>
      _api.post(ApiFunction.approveShiftApplicant,
          body: {'shiftId': shiftId, 'staffId': staffId});

  /// Nursery-only: declines an applicant. The shift keeps its capacity and
  /// stays open to others.
  Future<void> rejectApplicant({required String shiftId, required String staffId}) =>
      _api.post(ApiFunction.rejectShiftApplicant,
          body: {'shiftId': shiftId, 'staffId': staffId});

  Future<void> cancelShift(String shiftId) =>
      _api.post(ApiFunction.cancelShift, body: {'shiftId': shiftId});

  Future<void> markNoShow({required String shiftId, required String staffId}) =>
      _api.post(ApiFunction.markNoShow, body: {'shiftId': shiftId, 'staffId': staffId});
}
