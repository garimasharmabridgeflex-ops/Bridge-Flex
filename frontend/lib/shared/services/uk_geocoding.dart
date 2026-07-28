import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Reverse-geocodes a lat/lng into a human-readable UK place name (nearest
/// postcode's admin district) via postcodes.io — the same free, keyless API
/// already used for postcode autocomplete. Without this, GPS-detected
/// coordinates have no readable representation anywhere in the app; a raw
/// `52.4862, -1.8904` (or a geohash prefix like "gcpvj") means nothing to a
/// user glancing at their own profile.
Future<String?> reverseGeocodeUK(double lat, double lng) async {
  try {
    final uri = Uri.https('api.postcodes.io', '/postcodes', {
      'lon': lng.toString(),
      'lat': lat.toString(),
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (body['result'] as List?)?.cast<Map<String, dynamic>>();
    if (results == null || results.isEmpty) return null;
    final nearest = results.first;
    return nearest['admin_district'] as String? ?? nearest['parish'] as String?;
  } catch (_) {
    return null;
  }
}

/// Cached per (lat, lng) pair so the same coordinates aren't re-geocoded on
/// every rebuild.
final reverseGeocodeProvider =
    FutureProvider.autoDispose.family<String?, (double, double)>((ref, coords) {
  return reverseGeocodeUK(coords.$1, coords.$2);
});
