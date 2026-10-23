class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.description,
    required this.pricePence,
    required this.billingInterval,
    required this.bookingAllowance,
    required this.trialDays,
    required this.active,
    this.benefits = const [],
  });

  final String id;
  final String name;
  final String description;
  final int pricePence;
  final String billingInterval;
  final int bookingAllowance;
  final int trialDays;
  final bool active;
  final List<String> benefits;

  String get priceFormatted {
    if (pricePence == 0) return 'Free';
    return '£${(pricePence / 100.0).toStringAsFixed(2)}';
  }

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        pricePence: (json['pricePence'] as num?)?.toInt() ?? 0,
        billingInterval: json['billingInterval'] as String? ?? 'month',
        bookingAllowance: (json['bookingAllowance'] as num?)?.toInt() ?? 0,
        trialDays: (json['trialDays'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
        benefits: (json['benefits'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class TrialCountdown {
  const TrialCountdown({
    required this.daysRemaining,
    required this.isExpired,
  });

  final int daysRemaining;
  final bool isExpired;

  factory TrialCountdown.fromJson(Map<String, dynamic> json) => TrialCountdown(
        daysRemaining: (json['daysRemaining'] as num?)?.toInt() ?? 0,
        isExpired: json['isExpired'] as bool? ?? false,
      );
}

class NurserySubscription {
  const NurserySubscription({
    required this.nurseryId,
    required this.planId,
    required this.planName,
    required this.status,
    this.trialStartDate,
    this.trialEndDate,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.paymentMethod = 'bank_transfer',
    this.assignedByAdmin = false,
  });

  final String nurseryId;
  final String planId;
  final String planName;
  final String status;
  final DateTime? trialStartDate;
  final DateTime? trialEndDate;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String paymentMethod;
  final bool assignedByAdmin;

  bool get isTrialing => status == 'trialing';
  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';

  factory NurserySubscription.fromJson(Map<String, dynamic> json) {
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

    return NurserySubscription(
      nurseryId: json['nurseryId'] as String? ?? '',
      planId: json['planId'] as String? ?? 'trial',
      planName: json['planName'] as String? ?? 'Free Trial',
      status: json['status'] as String? ?? 'trialing',
      trialStartDate: parseDateOpt(json['trialStartDate']),
      trialEndDate: parseDateOpt(json['trialEndDate']),
      currentPeriodStart: parseDate(json['currentPeriodStart']),
      currentPeriodEnd: parseDate(json['currentPeriodEnd']),
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
      paymentMethod: json['paymentMethod'] as String? ?? 'bank_transfer',
      assignedByAdmin: json['assignedByAdmin'] as bool? ?? false,
    );
  }
}

class InvoiceLineItem {
  const InvoiceLineItem({
    required this.type,
    required this.description,
    required this.quantity,
    required this.unitPence,
    required this.totalPence,
    this.timesheetId,
    this.shiftId,
  });

  final String type;
  final String description;
  final double quantity;
  final int unitPence;
  final int totalPence;
  final String? timesheetId;
  final String? shiftId;

  String get totalFormatted => '£${(totalPence / 100.0).toStringAsFixed(2)}';

  factory InvoiceLineItem.fromJson(Map<String, dynamic> json) => InvoiceLineItem(
        type: json['type'] as String? ?? 'staffing',
        description: json['description'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
        unitPence: (json['unitPence'] as num?)?.toInt() ?? 0,
        totalPence: (json['totalPence'] as num?)?.toInt() ?? 0,
        timesheetId: json['timesheetId'] as String?,
        shiftId: json['shiftId'] as String?,
      );
}

class Invoice {
  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.nurseryId,
    required this.nurseryName,
    this.billingAddress = '',
    this.billingEmail = '',
    this.companyNumber = '',
    required this.issueDate,
    required this.dueDate,
    required this.status,
    required this.type,
    this.lineItems = const [],
    this.subtotalPence = 0,
    this.vatRate = 0.0,
    this.vatPence = 0,
    this.totalPence = 0,
    this.paymentMethod = 'bank_transfer',
    this.paidAt,
    this.paymentReference = '',
    this.notes = '',
  });

  final String id;
  final String invoiceNumber;
  final String nurseryId;
  final String nurseryName;
  final String billingAddress;
  final String billingEmail;
  final String companyNumber;
  final DateTime issueDate;
  final DateTime dueDate;
  final String status;
  final String type;
  final List<InvoiceLineItem> lineItems;
  final int subtotalPence;
  final double vatRate;
  final int vatPence;
  final int totalPence;
  final String paymentMethod;
  final DateTime? paidAt;
  final String paymentReference;
  final String notes;

  bool get isPaid => status == 'paid';
  bool get isIssued => status == 'issued';
  bool get isOverdue => status == 'overdue' || (!isPaid && DateTime.now().isAfter(dueDate));

  String get subtotalFormatted => '£${(subtotalPence / 100.0).toStringAsFixed(2)}';
  String get vatFormatted => '£${(vatPence / 100.0).toStringAsFixed(2)}';
  String get totalFormatted => '£${(totalPence / 100.0).toStringAsFixed(2)}';

  factory Invoice.fromJson(Map<String, dynamic> json) {
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

    final rawLines = (json['lineItems'] as List?) ?? const [];
    final items = rawLines
        .cast<Map<String, dynamic>>()
        .map((e) => InvoiceLineItem.fromJson(e))
        .toList();

    return Invoice(
      id: json['id'] as String? ?? '',
      invoiceNumber: json['invoiceNumber'] as String? ?? '',
      nurseryId: json['nurseryId'] as String? ?? '',
      nurseryName: json['nurseryName'] as String? ?? '',
      billingAddress: json['billingAddress'] as String? ?? '',
      billingEmail: json['billingEmail'] as String? ?? '',
      companyNumber: json['companyNumber'] as String? ?? '',
      issueDate: parseDate(json['issueDate']),
      dueDate: parseDate(json['dueDate']),
      status: json['status'] as String? ?? 'issued',
      type: json['type'] as String? ?? 'weekly_staffing',
      lineItems: items,
      subtotalPence: (json['subtotalPence'] as num?)?.toInt() ?? 0,
      vatRate: (json['vatRate'] as num?)?.toDouble() ?? 0.0,
      vatPence: (json['vatPence'] as num?)?.toInt() ?? 0,
      totalPence: (json['totalPence'] as num?)?.toInt() ?? 0,
      paymentMethod: json['paymentMethod'] as String? ?? 'bank_transfer',
      paidAt: parseDateOpt(json['paidAt']),
      paymentReference: json['paymentReference'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}
