import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Analytics was never wired into the app before — the Firebase
/// Console's Analytics dashboard read zero regardless of real traffic
/// because no SDK was sending it anything, not because tracking was broken.
final analyticsProvider = Provider<FirebaseAnalytics>((ref) => FirebaseAnalytics.instance);

/// Passed to GoRouter's `observers` (router.dart) to automatically log a
/// `screen_view` event on every navigation, with no per-screen wiring needed.
final analyticsObserverProvider = Provider<FirebaseAnalyticsObserver>(
  (ref) => FirebaseAnalyticsObserver(analytics: ref.watch(analyticsProvider)),
);
