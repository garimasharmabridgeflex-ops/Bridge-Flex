import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';

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
}
