class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.read,
    required this.createdAt,
    this.body,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime? createdAt;
  final String? body;

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: json['notificationId'] as String,
        type: json['type'] as String? ?? '',
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        read: json['read'] as bool? ?? false,
        createdAt: _parseTimestamp(json['createdAt']),
        body: json['body'] as String?,
      );

  static DateTime? _parseTimestamp(Object? value) {
    if (value is Map && value['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((value['_seconds'] as num).toInt() * 1000);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String get title => switch (type) {
        'shift_booked' => 'Shift booked',
        'new_matching_shift' => 'New shift available',
        'rating_received' => 'You received a rating',
        'shift_cancelled' => 'Shift cancelled',
        'shift_uncovered' => 'Shift needs covering',
        _ => 'Notification',
      };

  String get subtitle => body ??
      switch (type) {
        'shift_booked' => 'Your shift booking was confirmed.',
        'new_matching_shift' => 'A new shift matching your area is available.',
        'rating_received' => 'A nursery left you a rating. Tap to view.',
        'shift_cancelled' => 'A shift you were involved in was cancelled.',
        'shift_uncovered' => 'A shift you covered was just made available again.',
        _ => '',
      };
}

