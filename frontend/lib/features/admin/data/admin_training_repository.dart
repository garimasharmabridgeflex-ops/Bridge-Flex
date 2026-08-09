import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/admin_training_module.dart';

/// Admin authoring of training modules.
///
/// Unlike the practitioner-facing repository, the responses here DO include
/// each question's correct answer — that is the whole point of the admin
/// endpoints, and they are gated on the Firebase admin custom claim
/// server-side.
class AdminTrainingRepository {
  AdminTrainingRepository(this._api);

  final ApiClient _api;

  Future<List<AdminTrainingModule>> list() async {
    final res = await _api.post(ApiFunction.listTrainingModulesAdmin);
    return ((res['modules'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(AdminTrainingModule.fromJson)
        .toList();
  }

  /// Creates or replaces a module. The backend validates that every question
  /// has at least two options and a correctIndex inside range, and refuses to
  /// publish a module with no questions at all.
  Future<void> upsert(AdminTrainingModule module) =>
      _api.post(ApiFunction.upsertTrainingModule, body: module.toJson());

  Future<void> delete(String moduleId) =>
      _api.post(ApiFunction.deleteTrainingModule, body: {'moduleId': moduleId});
}
