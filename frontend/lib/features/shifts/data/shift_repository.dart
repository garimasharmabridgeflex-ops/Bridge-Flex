import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/shift.dart';

class ShiftRepository {
  ShiftRepository(this._api);

  final ApiClient _api;

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
  }) {
    return _api.post(ApiFunction.updateShift, body: {
      'shiftId': shiftId,
      if (title != null) 'title': title,
      if (date != null) 'date': date,
      if (startTime != null) 'startTime': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'endTime': endTime.toUtc().toIso8601String(),
      if (payRate != null) 'payRate': payRate,
    });
  }

  Future<void> acceptShift(String shiftId) =>
      _api.post(ApiFunction.acceptShift, body: {'shiftId': shiftId});

  Future<void> cancelShift(String shiftId) =>
      _api.post(ApiFunction.cancelShift, body: {'shiftId': shiftId});

  Future<void> markNoShow({required String shiftId, required String staffId}) =>
      _api.post(ApiFunction.markNoShow, body: {'shiftId': shiftId, 'staffId': staffId});
}
