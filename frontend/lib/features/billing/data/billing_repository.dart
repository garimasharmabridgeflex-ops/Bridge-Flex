import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/billing_models.dart';

class BillingRepository {
  BillingRepository(this._api);

  final ApiClient _api;

  Future<List<Plan>> getPlans() async {
    final res = await _api.post(ApiFunction.getPlans);
    final raw = (res['plans'] as List?) ?? const [];
    return raw
        .cast<Map<String, dynamic>>()
        .map((e) => Plan.fromJson(e))
        .toList();
  }

  Future<({NurserySubscription subscription, TrialCountdown trial})> getNurserySubscription({
    String? nurseryId,
  }) async {
    final query = <String, String>{
      if (nurseryId != null && nurseryId.isNotEmpty) 'nurseryId': nurseryId,
    };
    final res = await _api.postWithQuery(ApiFunction.getNurserySubscription, query: query);
    final sub = NurserySubscription.fromJson(res['subscription'] as Map<String, dynamic>);
    final trial = TrialCountdown.fromJson(res['trial'] as Map<String, dynamic>? ?? const {});
    return (subscription: sub, trial: trial);
  }

  Future<NurserySubscription> assignPlan({
    required String nurseryId,
    required String planId,
  }) async {
    final res = await _api.post(
      ApiFunction.assignNurseryPlan,
      body: {
        'nurseryId': nurseryId,
        'planId': planId,
      },
    );
    return NurserySubscription.fromJson(res);
  }

  Future<List<Invoice>> listInvoices({
    String? nurseryId,
    String? status,
  }) async {
    final query = <String, String>{
      if (nurseryId != null && nurseryId.isNotEmpty) 'nurseryId': nurseryId,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final res = await _api.postWithQuery(ApiFunction.listInvoices, query: query);
    final raw = (res['invoices'] as List?) ?? const [];
    return raw
        .cast<Map<String, dynamic>>()
        .map((e) => Invoice.fromJson(e))
        .toList();
  }

  Future<Invoice> getInvoice(String invoiceId) async {
    final res = await _api.postWithQuery(
      ApiFunction.getInvoice,
      query: {'invoiceId': invoiceId},
    );
    return Invoice.fromJson(res['invoice'] as Map<String, dynamic>);
  }

  Future<void> markInvoicePaid({
    required String invoiceId,
    required String paymentReference,
    String? notes,
  }) async {
    await _api.post(
      ApiFunction.markInvoicePaid,
      body: {
        'invoiceId': invoiceId,
        'paymentReference': paymentReference,
        'notes': ?notes,
      },
    );
  }
}
