/// One individual review left for a user — backend/services/core/function/
/// ratings.go listRatings. Distinct from [RatingSummary]/[RatingBreakdown]
/// (profile.dart), which are aggregates; this is a single review row.
class Review {
  const Review({
    required this.ratingId,
    required this.raterId,
    required this.score,
    required this.comment,
    required this.createdAt,
  });

  final String ratingId;
  final String raterId;
  final int score;
  final String comment;
  final DateTime? createdAt;

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        ratingId: json['ratingId'] as String? ?? '',
        raterId: json['raterId'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        comment: json['comment'] as String? ?? '',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );
}
