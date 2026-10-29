import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/payroll_models.dart';

class PayrollRepository {
  PayrollRepository(this._api);

  final ApiClient _api;

  Future<PayrollProfile> getPayrollProfile({String? uid}) async {
    final query = <String, String>{
      if (uid != null && uid.isNotEmpty) 'uid': uid,
    };
    final res = await _api.postWithQuery(ApiFunction.getPayrollProfile, query: query);
    return PayrollProfile.fromJson(res);
  }

  Future<PayrollProfile> updatePayrollProfile({
    String? uid,
    String? bankAccountName,
    String? bankAccountNumber,
    String? bankSortCode,
    String? nationalInsuranceNumber,
    bool? eligibleForRolledUpHolidayPay,
  }) async {
    final body = <String, dynamic>{
      'uid': ?uid,
      'bankAccountName': ?bankAccountName,
      'bankAccountNumber': ?bankAccountNumber,
      'bankSortCode': ?bankSortCode,
      'nationalInsuranceNumber': ?nationalInsuranceNumber,
      'eligibleForRolledUpHolidayPay': ?eligibleForRolledUpHolidayPay,
    };
    final res = await _api.post(ApiFunction.updatePayrollProfile, body: body);
    return PayrollProfile.fromJson(res);
  }

  Future<PractitionerEarningsSummary> getPractitionerEarnings() async {
    final res = await _api.post(ApiFunction.getPractitionerEarnings);
    return PractitionerEarningsSummary.fromJson(res);
  }

  Future<Map<String, dynamic>> generatePayrollPeriod({
    required DateTime startDate,
    required DateTime endDate,
    String? periodName,
  }) async {
    final body = <String, dynamic>{
      'startDate': startDate.toUtc().toIso8601String(),
      'endDate': endDate.toUtc().toIso8601String(),
      'periodName': ?periodName,
    };
    return _api.post(ApiFunction.generatePayrollPeriod, body: body);
  }

  Future<void> markPayrollPeriodPaid(String periodId) async {
    await _api.post(
      ApiFunction.markPayrollPeriodPaid,
      body: {'periodId': periodId},
    );
  }
}
