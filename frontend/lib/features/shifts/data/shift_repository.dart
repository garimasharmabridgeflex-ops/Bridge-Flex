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
