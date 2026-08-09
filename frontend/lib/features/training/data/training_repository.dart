import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/training_module.dart';

class TrainingRepository {
  TrainingRepository(this._api, this._storage);

  final ApiClient _api;
  final FirebaseStorage _storage;

  Future<TrainingOverview> list() async {
    final res = await _api.post(ApiFunction.listTrainingModules);
    return TrainingOverview.fromJson(res);
  }

  /// Resolves a module's video to a playable URL.
  ///
  /// Storage path wins over an explicit url: it's resolved through
  /// getDownloadURL() so playback goes through Storage's auth rules (signed-in
  /// read), and re-uploading over the same path swaps the video without any
  /// change to the module document.
  Future<String?> resolveVideoUrl(TrainingModule module) async {
    if (module.videoStoragePath.isNotEmpty) {
      return _storage.ref(module.videoStoragePath).getDownloadURL();
    }
    if (module.videoUrl.isNotEmpty) return module.videoUrl;
    return null;
  }

  Future<void> markVideoWatched(String moduleId) =>
      _api.post(ApiFunction.markTrainingVideoWatched, body: {'moduleId': moduleId});

  /// Submits answers for grading. Answers are scored on the server; the app
  /// never knows which option was correct until the result comes back.
  Future<QuizResult> submitQuiz(String moduleId, Map<String, int> answers) async {
    final res = await _api.post(ApiFunction.submitTrainingQuiz, body: {
      'moduleId': moduleId,
      'answers': answers.entries
          .map((e) => {'questionId': e.key, 'selectedIndex': e.value})
          .toList(),
    });
    return QuizResult.fromJson(res);
  }
}
