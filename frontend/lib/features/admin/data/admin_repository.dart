import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/admin_models.dart';

class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<PlatformStats> getPlatformStats() async {
    final res = await _api.post(ApiFunction.getPlatformStats);
    return PlatformStats.fromJson(res);
  }

  Future<List<AdminUserSummary>> listAllUsers() async {
    final res = await _api.post(ApiFunction.listAllUsers);
    final list = (res['users'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return list.map(AdminUserSummary.fromJson).toList();
  }

  Future<AdminUserDetail> getUserDetail(String uid) async {
    final res = await _api.post(ApiFunction.getUserDetail, body: {'uid': uid});
    return AdminUserDetail.fromJson(res);
  }

  Future<void> setUserSuspended({required String uid, required bool suspended}) {
    return _api.post(ApiFunction.setUserSuspended, body: {'uid': uid, 'suspended': suspended});
  }

  Future<void> setVerificationBadge({
    required String uid,
    required String badge,
    required bool verified,
  }) {
    return _api.post(ApiFunction.setVerificationBadge, body: {
      'uid': uid,
      'badge': badge,
      'verified': verified,
    });
  }
}
