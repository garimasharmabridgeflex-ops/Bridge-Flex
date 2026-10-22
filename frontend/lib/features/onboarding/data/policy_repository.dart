import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';

final policyRepositoryProvider = Provider<PolicyRepository>((ref) {
  return PolicyRepository(ref.watch(apiClientProvider));
});

class RequiredPolicy {
  const RequiredPolicy({
    required this.id,
    required this.type,
    required this.version,
    required this.title,
    required this.content,
    this.summary,
  });

  final String id;
  final String type;
  final int version;
  final String title;
  final String content;
  final String? summary;

  factory RequiredPolicy.fromJson(Map<String, dynamic> json) {
    return RequiredPolicy(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? 'Terms and Policies',
      content: json['content'] as String? ?? '',
      summary: json['summary'] as String?,
    );
  }
}

class PolicyRepository {
  const PolicyRepository(this._api);

  final ApiClient _api;

  Future<List<RequiredPolicy>> fetchRequiredPolicies({String role = 'staff'}) async {
    try {
      final res = await _api.postWithQuery(ApiFunction.getRequiredPolicies, query: {'role': role});
      final list = (res['policies'] as List?) ?? [];
      return list.map((e) => RequiredPolicy.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (_) {
      // Offline fallback: provide core standard policies
      return [
        const RequiredPolicy(
          id: 'default_terms',
          type: 'terms',
          version: 1,
          title: 'Terms of Service',
          content: 'I agree to the K Flex platform terms and conditions of service.',
        ),
        const RequiredPolicy(
          id: 'default_privacy',
          type: 'privacy',
          version: 1,
          title: 'Privacy Policy',
          content: 'I have read and agree to the K Flex data privacy policy.',
        ),
        const RequiredPolicy(
          id: 'default_safeguarding',
          type: 'safeguarding',
          version: 1,
          title: 'Safeguarding Policy',
          content: 'I agree to strictly abide by childcare safeguarding standards and reporting requirements.',
        ),
      ];
    }
  }

  Future<void> acceptPolicies(List<RequiredPolicy> policies, {String appVersion = '1.6.0'}) async {
    final acceptances = policies
        .map((p) => {
              'policyType': p.type,
              'version': p.version,
            })
        .toList();

    await _api.post(
      ApiFunction.acceptPolicies,
      body: {
        'acceptances': acceptances,
        'appVersion': appVersion,
      },
    );
  }
}
