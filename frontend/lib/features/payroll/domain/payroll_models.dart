import '../../timesheets/domain/timesheet.dart';

class PayrollProfile {
  const PayrollProfile({
    required this.uid,
    this.bankAccountName = '',
    this.bankAccountNumberMasked = '',
    this.bankSortCode = '',
    this.nationalInsuranceNumberMasked = '',
    this.eligibleForRolledUpHolidayPay = false,
  });

  final String uid;
  final String bankAccountName;
  final String bankAccountNumberMasked;
  final String bankSortCode;
  final String nationalInsuranceNumberMasked;
  final bool eligibleForRolledUpHolidayPay;

  factory PayrollProfile.fromJson(Map<String, dynamic> json) => PayrollProfile(
        uid: json['uid'] as String? ?? '',
        bankAccountName: json['bankAccountName'] as String? ?? '',
        bankAccountNumberMasked: json['bankAccountNumberMasked'] as String? ?? '',
        bankSortCode: json['bankSortCode'] as String? ?? '',
        nationalInsuranceNumberMasked: json['nationalInsuranceNumberMasked'] as String? ?? '',
        eligibleForRolledUpHolidayPay: json['eligibleForRolledUpHolidayPay'] as bool? ?? false,
      );
}

class Payslip {
  const Payslip({
    required this.id,
    required this.practitionerId,
    required this.periodId,
    required this.periodName,
    required this.storagePath,
    required this.fileName,
    required this.uploadedAt,
  });

  final String id;
  final String practitionerId;
  final String periodId;
  final String periodName;
  final String storagePath;
  final String fileName;
  final DateTime uploadedAt;

  factory Payslip.fromJson(Map<String, dynamic> json) => Payslip(
        id: json['id'] as String? ?? '',
        practitionerId: json['practitionerId'] as String? ?? '',
        periodId: json['periodId'] as String? ?? '',
        periodName: json['periodName'] as String? ?? '',
        storagePath: json['storagePath'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        uploadedAt: DateTime.tryParse(json['uploadedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class PractitionerEarningsSummary {
  const PractitionerEarningsSummary({
    required this.totalCompletedShifts,
    required this.totalBillableMinutes,
    required this.totalGrossPayPence,
    required this.totalBasicPayPence,
    required this.totalHolidayPayPence,
    required this.eligibleForRolledUpHolidayPay,
    required this.recentTimesheets,
    required this.payslips,
  });

  final int totalCompletedShifts;
  final int totalBillableMinutes;
  final int totalGrossPayPence;
  final int totalBasicPayPence;
  final int totalHolidayPayPence;
  final bool eligibleForRolledUpHolidayPay;
  final List<Timesheet> recentTimesheets;
  final List<Payslip> payslips;

  String get grossPayFormatted => '£${(totalGrossPayPence / 100.0).toStringAsFixed(2)}';
  String get basicPayFormatted => '£${(totalBasicPayPence / 100.0).toStringAsFixed(2)}';
  String get holidayPayFormatted => '£${(totalHolidayPayPence / 100.0).toStringAsFixed(2)}';

  String get billableHoursFormatted {
    final hours = totalBillableMinutes ~/ 60;
    final mins = totalBillableMinutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  factory PractitionerEarningsSummary.fromJson(Map<String, dynamic> json) {
    final rawTs = (json['recentTimesheets'] as List?) ?? const [];
    final timesheets = rawTs
        .cast<Map<String, dynamic>>()
        .map((e) => Timesheet.fromJson(e))
        .toList();

    final rawPs = (json['payslips'] as List?) ?? const [];
    final payslips = rawPs
        .cast<Map<String, dynamic>>()
        .map((e) => Payslip.fromJson(e))
        .toList();

    return PractitionerEarningsSummary(
      totalCompletedShifts: (json['totalCompletedShifts'] as num?)?.toInt() ?? 0,
      totalBillableMinutes: (json['totalBillableMinutes'] as num?)?.toInt() ?? 0,
      totalGrossPayPence: (json['totalGrossPayPence'] as num?)?.toInt() ?? 0,
      totalBasicPayPence: (json['totalBasicPayPence'] as num?)?.toInt() ?? 0,
      totalHolidayPayPence: (json['totalHolidayPayPence'] as num?)?.toInt() ?? 0,
      eligibleForRolledUpHolidayPay: json['eligibleForRolledUpHolidayPay'] as bool? ?? false,
      recentTimesheets: timesheets,
      payslips: payslips,
    );
  }
}
