import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/timesheet.dart';

class TimesheetRepository {
  TimesheetRepository(this._api, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _firestore;

  /// Live real-time Firestore stream of the timesheet document for a given
  /// shift. This replaces the previous 6-second HTTP polling loop, so a
  /// submission, correction, dispute or approval appears on the other
  /// party's screen the moment it is written.
  ///
  /// Firestore rules only let a participant read their own timesheet, so the
  /// query must always be narrowed to something the viewer is allowed to
  /// read: [staffId] for the practitioner, [nurseryId] for the setting, or no
  /// extra filter for an admin (whose claim grants read of every timesheet).
  Stream<Timesheet?> watchTimesheetForShift(
    String shiftId, {
    String? staffId,
    String? nurseryId,
  }) {
    Query<Map<String, dynamic>> query =
        _firestore.collection('timesheets').where('shiftId', isEqualTo: shiftId);
    if (staffId != null) {
      query = query.where('staffId', isEqualTo: staffId);
    } else if (nurseryId != null) {
      query = query.where('nurseryId', isEqualTo: nurseryId);
    }
    return query.limit(1).snapshots().map((snap) {
      if (snap.docs.isEmpty) return null;
      return Timesheet.fromFirestore(snap.docs.first);
    });
  }

  /// Practitioner submits recorded hours for a completed shift.
  Future<Timesheet> submitTimesheet({
    required String shiftId,
    DateTime? actualStartTime,
    DateTime? actualEndTime,
    int? unpaidBreakMinutes,
  }) async {
    final body = <String, dynamic>{
      'shiftId': shiftId,
      if (actualStartTime != null) 'actualStartTime': actualStartTime.toUtc().toIso8601String(),
      if (actualEndTime != null) 'actualEndTime': actualEndTime.toUtc().toIso8601String(),
      if (unpaidBreakMinutes != null) 'unpaidBreakMinutes': unpaidBreakMinutes,
    };
    final res = await _api.post(ApiFunction.submitTimesheet, body: body);
    return Timesheet.fromJson(res);
  }

  /// Fetches a timesheet by ID, or by shiftId and optional staffId.
  Future<Timesheet?> getTimesheet({
    String? timesheetId,
    String? shiftId,
    String? staffId,
  }) async {
    try {
      final query = <String, String>{
        if (timesheetId != null && timesheetId.isNotEmpty) 'timesheetId': timesheetId,
        if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
        if (staffId != null && staffId.isNotEmpty) 'staffId': staffId,
      };
      final res = await _api.postWithQuery(ApiFunction.getTimesheet, query: query);
      return Timesheet.fromJson(res);
    } catch (_) {
      return null;
    }
  }

  /// Lists timesheets with optional filters.
  Future<List<Timesheet>> listTimesheets({
    String? shiftId,
    String? staffId,
    String? nurseryId,
    String? status,
  }) async {
    final query = <String, String>{
      if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
      if (staffId != null && staffId.isNotEmpty) 'staffId': staffId,
      if (nurseryId != null && nurseryId.isNotEmpty) 'nurseryId': nurseryId,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final res = await _api.postWithQuery(ApiFunction.listTimesheets, query: query);
    final raw = (res['timesheets'] as List?) ?? const [];
    return raw
        .cast<Map<String, dynamic>>()
        .map((e) => Timesheet.fromJson(e))
        .toList();
  }

  /// Nursery approves the submitted timesheet hours.
  Future<Timesheet> approveTimesheet({
    required String timesheetId,
    String? feedback,
  }) async {
    final res = await _api.post(
      ApiFunction.approveTimesheet,
      body: {
        'timesheetId': timesheetId,
        if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
      },
    );
    return Timesheet.fromJson(res);
  }

  /// Nursery requests corrections on the recorded hours.
  Future<Timesheet> requestCorrection({
    required String timesheetId,
    required String feedback,
  }) async {
    final res = await _api.post(
      ApiFunction.requestTimesheetCorrection,
      body: {
        'timesheetId': timesheetId,
        'feedback': feedback,
      },
    );
    return Timesheet.fromJson(res);
  }

  /// Nursery formally reports an attendance or hours dispute.
  Future<Timesheet> disputeTimesheet({
    required String timesheetId,
    required String reason,
  }) async {
    final res = await _api.post(
      ApiFunction.disputeTimesheet,
      body: {
        'timesheetId': timesheetId,
        'reason': reason,
      },
    );
    return Timesheet.fromJson(res);
  }

  /// Admin resolves a timesheet dispute or approves escalated hours.
  Future<Timesheet> adminApproveTimesheet({
    required String timesheetId,
    DateTime? actualStartTime,
    DateTime? actualEndTime,
    int? unpaidBreakMinutes,
    required String adminNotes,
  }) async {
    final res = await _api.post(
      ApiFunction.adminApproveTimesheet,
      body: {
        'timesheetId': timesheetId,
        if (actualStartTime != null) 'actualStartTime': actualStartTime.toUtc().toIso8601String(),
        if (actualEndTime != null) 'actualEndTime': actualEndTime.toUtc().toIso8601String(),
        if (unpaidBreakMinutes != null) 'unpaidBreakMinutes': unpaidBreakMinutes,
        'adminNotes': adminNotes,
      },
    );
    return Timesheet.fromJson(res);
  }
}
