import 'package:cloud_firestore/cloud_firestore.dart';

enum TimesheetStatus {
  submitted,
  approved,
  correctionRequested,
  disputed,
  adminApproved;

  static TimesheetStatus fromString(String val) {
    switch (val) {
      case 'approved':
        return TimesheetStatus.approved;
      case 'correction_requested':
        return TimesheetStatus.correctionRequested;
      case 'disputed':
        return TimesheetStatus.disputed;
      case 'admin_approved':
        return TimesheetStatus.adminApproved;
      case 'submitted':
      default:
        return TimesheetStatus.submitted;
    }
  }

  String toServerString() {
    switch (this) {
      case TimesheetStatus.approved:
        return 'approved';
      case TimesheetStatus.correctionRequested:
        return 'correction_requested';
      case TimesheetStatus.disputed:
        return 'disputed';
      case TimesheetStatus.adminApproved:
        return 'admin_approved';
      case TimesheetStatus.submitted:
        return 'submitted';
    }
  }

  String get label {
    switch (this) {
      case TimesheetStatus.submitted:
        return 'Submitted (Pending Review)';
      case TimesheetStatus.approved:
        return 'Approved';
      case TimesheetStatus.correctionRequested:
        return 'Correction Requested';
      case TimesheetStatus.disputed:
        return 'Disputed (Under Admin Review)';
      case TimesheetStatus.adminApproved:
        return 'Admin Approved';
    }
  }
}

class Timesheet {
  const Timesheet({
    required this.id,
    required this.shiftId,
    required this.nurseryId,
    required this.staffId,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
    required this.actualStartTime,
    required this.actualEndTime,
    this.unpaidBreakMinutes = 0,
    this.billableMinutes = 0,
    this.hourlyRatePence = 0,
    this.nurseryHourlyRatePence = 0,
    this.totalGrossPayPence = 0,
    this.totalNurseryChargePence = 0,
    required this.status,
    this.nurseryFeedback = '',
    this.disputeReason = '',
    this.adminNotes = '',
    this.submittedAt,
    this.decidedAt,
    this.escalatedAt,
  });

  final String id;
  final String shiftId;
  final String nurseryId;
  final String staffId;
  final DateTime scheduledStartTime;
  final DateTime scheduledEndTime;
  final DateTime actualStartTime;
  final DateTime actualEndTime;
  final int unpaidBreakMinutes;
  final int billableMinutes;
  final int hourlyRatePence;
  final int nurseryHourlyRatePence;
  final int totalGrossPayPence;
  final int totalNurseryChargePence;
  final TimesheetStatus status;
  final String nurseryFeedback;
  final String disputeReason;
  final String adminNotes;
  final DateTime? submittedAt;
  final DateTime? decidedAt;
  final DateTime? escalatedAt;

  bool get isApproved =>
      status == TimesheetStatus.approved || status == TimesheetStatus.adminApproved;
  bool get isPendingReview => status == TimesheetStatus.submitted;
  bool get isCorrectionRequested => status == TimesheetStatus.correctionRequested;
  bool get isDisputed => status == TimesheetStatus.disputed;
  bool get isEscalated => escalatedAt != null;

  double get billableHours => billableMinutes / 60.0;
  String get billableHoursFormatted {
    final hours = billableMinutes ~/ 60;
    final mins = billableMinutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  String get grossPayFormatted => '£${(totalGrossPayPence / 100.0).toStringAsFixed(2)}';
  String get nurseryChargeFormatted => '£${(totalNurseryChargePence / 100.0).toStringAsFixed(2)}';

  factory Timesheet.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is DateTime) return v;
      return DateTime.now();
    }

    DateTime? parseDateOpt(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      if (v is DateTime) return v;
      return null;
    }

    return Timesheet(
      id: json['id'] as String? ?? '',
      shiftId: json['shiftId'] as String? ?? '',
      nurseryId: json['nurseryId'] as String? ?? '',
      staffId: json['staffId'] as String? ?? '',
      scheduledStartTime: parseDate(json['scheduledStartTime']),
      scheduledEndTime: parseDate(json['scheduledEndTime']),
      actualStartTime: parseDate(json['actualStartTime']),
      actualEndTime: parseDate(json['actualEndTime']),
      unpaidBreakMinutes: (json['unpaidBreakMinutes'] as num?)?.toInt() ?? 0,
      billableMinutes: (json['billableMinutes'] as num?)?.toInt() ?? 0,
      hourlyRatePence: (json['hourlyRatePence'] as num?)?.toInt() ?? 0,
      nurseryHourlyRatePence: (json['nurseryHourlyRatePence'] as num?)?.toInt() ?? 0,
      totalGrossPayPence: (json['totalGrossPayPence'] as num?)?.toInt() ?? 0,
      totalNurseryChargePence: (json['totalNurseryChargePence'] as num?)?.toInt() ?? 0,
      status: TimesheetStatus.fromString(json['status'] as String? ?? 'submitted'),
      nurseryFeedback: json['nurseryFeedback'] as String? ?? '',
      disputeReason: json['disputeReason'] as String? ?? '',
      adminNotes: json['adminNotes'] as String? ?? '',
      submittedAt: parseDateOpt(json['submittedAt']),
      decidedAt: parseDateOpt(json['decidedAt']),
      escalatedAt: parseDateOpt(json['escalatedAt']),
    );
  }

  factory Timesheet.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is DateTime) return v;
      return DateTime.now();
    }

    DateTime? parseDateOpt(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      if (v is DateTime) return v;
      return null;
    }

    return Timesheet(
      id: doc.id,
      shiftId: data['shiftId'] as String? ?? '',
      nurseryId: data['nurseryId'] as String? ?? '',
      staffId: data['staffId'] as String? ?? '',
      scheduledStartTime: parseDate(data['scheduledStartTime']),
      scheduledEndTime: parseDate(data['scheduledEndTime']),
      actualStartTime: parseDate(data['actualStartTime']),
      actualEndTime: parseDate(data['actualEndTime']),
      unpaidBreakMinutes: (data['unpaidBreakMinutes'] as num?)?.toInt() ?? 0,
      billableMinutes: (data['billableMinutes'] as num?)?.toInt() ?? 0,
      hourlyRatePence: (data['hourlyRatePence'] as num?)?.toInt() ?? 0,
      nurseryHourlyRatePence: (data['nurseryHourlyRatePence'] as num?)?.toInt() ?? 0,
      totalGrossPayPence: (data['totalGrossPayPence'] as num?)?.toInt() ?? 0,
      totalNurseryChargePence: (data['totalNurseryChargePence'] as num?)?.toInt() ?? 0,
      status: TimesheetStatus.fromString(data['status'] as String? ?? 'submitted'),
      nurseryFeedback: data['nurseryFeedback'] as String? ?? '',
      disputeReason: data['disputeReason'] as String? ?? '',
      adminNotes: data['adminNotes'] as String? ?? '',
      submittedAt: parseDateOpt(data['submittedAt']),
      decidedAt: parseDateOpt(data['decidedAt']),
      escalatedAt: parseDateOpt(data['escalatedAt']),
    );
  }
}
