import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.read,
    required this.createdAt,
    this.titleText,
    this.body,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime? createdAt;
  final String? titleText;
  final String? body;

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: json['notificationId'] as String? ?? json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        read: json['read'] as bool? ?? false,
        createdAt: _parseTimestamp(json['createdAt']),
        titleText: json['title'] as String?,
        body: json['body'] as String?,
      );

  factory NotificationItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return NotificationItem(
      id: doc.id,
      type: data['type'] as String? ?? '',
      payload: (data['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      read: data['read'] as bool? ?? false,
      createdAt: _parseTimestamp(data['createdAt']),
      titleText: data['title'] as String?,
      body: data['body'] as String?,
    );
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is Map && value['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((value['_seconds'] as num).toInt() * 1000);
    }
    // toLocal() is required, not cosmetic. The backend serializes timestamps
    // as RFC 3339 UTC, so tryParse returns a DateTime with isUtc: true, and
    // DateFormat renders whatever zone the DateTime carries — printing the
    // same UTC clock time on a device in Nairobi and one in London. Relative
    // labels ("9 minutes ago") looked correct regardless, because difference()
    // compares instants and ignores the zone flag.
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  String get title {
    if (titleText != null && titleText!.isNotEmpty) return titleText!;
    return switch (type) {
      'shift_booked' => 'Shift booked',
      'shift_application' => 'New applicant',
      'shift_application_approved' => 'Application approved',
      'shift_application_declined' => 'Application update',
      'timesheet_submitted' => 'Timesheet submitted',
      'timesheet_approved' => 'Timesheet approved',
      'timesheet_correction_requested' => 'Timesheet needs correction',
      'new_matching_shift' => 'New shift available',
      'rating_received' => 'You received a rating',
      'shift_cancelled' => 'Shift cancelled',
      'shift_uncovered' => 'Shift needs covering',
      _ => 'Notification',
    };
  }

  String get subtitle => body ??
      switch (type) {
        'shift_booked' => 'Your shift booking was confirmed.',
        'shift_application' => 'A practitioner applied for your shift.',
        'shift_application_approved' => 'Your shift application was approved!',
        'shift_application_declined' => 'Your application was not selected for this shift.',
        'timesheet_submitted' => 'A practitioner submitted hours for a shift. Tap to review.',
        'timesheet_approved' => 'Your timesheet was approved.',
        'timesheet_correction_requested' => 'The nursery requested changes to your timesheet.',
        'new_matching_shift' => 'A new shift matching your area is available.',
        'rating_received' => 'A nursery left you a rating. Tap to view.',
        'shift_cancelled' => 'A shift you were involved in was cancelled.',
        'shift_uncovered' => 'A shift you covered was just made available again.',
        _ => '',
      };
}

