import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/billing_models.dart';

class BillingRepository {
  BillingRepository(this._api, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _firestore;

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

  /// Live Firestore stream of a nursery's invoices — the same client-legal
  /// `nurseryId == <uid>` query listInvoices runs server-side, sorted
  /// client-side by issueDate (no composite index needed). This is what makes
  /// a freshly generated weekly invoice appear the moment it is written
  /// instead of on the next heartbeat tick.
  Stream<List<Invoice>> watchInvoices(String nurseryId) {
    return _firestore
        .collection('invoices')
        .where('nurseryId', isEqualTo: nurseryId)
        .snapshots()
        .map((snap) {
      final invoices = snap.docs
          .map((d) => Invoice.fromFirestore(d.data(), d.id))
          .toList();
      invoices.sort((a, b) => b.issueDate.compareTo(a.issueDate));
      return invoices;
    });
  }

  Future<Invoice> getInvoice(String invoiceId) async {
    final res = await _api.postWithQuery(
      ApiFunction.getInvoice,
      query: {'invoiceId': invoiceId},
    );
    return Invoice.fromJson(res['invoice'] as Map<String, dynamic>);
  }

  /// Starts Stripe Checkout for a nursery plan. Returns `url: null` when the
  /// nursery already has a live card subscription and the change was applied
  /// to that subscription in place (Stripe prorates it) — no redirect needed.
  Future<({String? url, bool updated})> createCheckoutSession({
    required String planId,
  }) async {
    final res = await _api.post(
      ApiFunction.createSubscriptionCheckout,
      body: {'planId': planId},
    );
    final url = res['url'] as String?;
    final updated = res['updated'] as bool? ?? false;
    return (url: (url == null || url.isEmpty) ? null : url, updated: updated);
  }

  /// Opens Stripe's hosted billing portal (update card, receipts, cancel).
  Future<String> createBillingPortalSession() async {
    final res = await _api.post(ApiFunction.createBillingPortalSession);
    final url = res['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Stripe did not return a billing portal URL');
    }
    return url;
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
