import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/env.dart';
import '../domain/review.dart';

class RatingsRepository {
  RatingsRepository(this._api, [FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final ApiClient _api;
  final FirebaseFirestore _firestore;

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

  /// Live stream of every review left for [uid], newest first — the same set
  /// listRatings returns (rules allow any signed-in user to read ratings).
  /// Sorted client-side under the same 50-row cap the HTTP mirror applies:
  /// rateeId equality + createdAt ordering would need a composite index that
  /// isn't deployed, and the mirror deliberately avoids orderBy for the same
  /// reason (see ratings.go / chat.go notes).
  Stream<List<Review>> watchRatings(String uid) {
    return _firestore
        .collection('ratings')
        .where('rateeId', isEqualTo: uid)
        .limit(50)
        .snapshots()
        .map((snap) {
      final reviews = snap.docs.map(Review.fromFirestore).toList();
      reviews.sort((a, b) =>
          (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      return reviews;
    });
  }
}
