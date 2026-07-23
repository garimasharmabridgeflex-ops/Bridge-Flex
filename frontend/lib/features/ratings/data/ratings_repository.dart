import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/review.dart';

class RatingsRepository {
  RatingsRepository(this._api);

  final ApiClient _api;

  Future<void> rate({
    required String shiftId,
    required String rateeId,
    required int score,
    String comment = '',
  }) {
    return _api.post(ApiFunction.createRating, body: {
      'shiftId': shiftId,
      'rateeId': rateeId,
      'score': score,
      'comment': comment,
    });
  }

  /// Every individual review left for [uid] — backs a profile's reviews
  /// list (full app spec: both reference designs show named reviewers with
  /// comments and dates, not just the aggregate average).
  Future<List<Review>> listRatings(String uid) async {
    final res = await _api.postWithQuery(ApiFunction.listRatings, query: {'uid': uid});
    final list = (res['ratings'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return list.map(Review.fromJson).toList();
  }
}
