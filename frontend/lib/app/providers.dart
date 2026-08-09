import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_repository.dart';
import '../features/admin/data/admin_training_repository.dart';
import '../features/admin/domain/admin_training_module.dart';
import '../features/training/data/training_repository.dart';
import '../features/training/domain/training_module.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/chat/data/chat_repository.dart';
import '../features/documents/data/documents_repository.dart';
import '../features/notifications/data/notifications_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/profile/domain/profile.dart';
import '../features/ratings/data/ratings_repository.dart';
import '../features/shifts/data/shift_repository.dart';
import 'firestore_provider.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firebaseStorageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(firebaseAuthProvider)));

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(firestoreProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider), ref.watch(firebaseStorageProvider)),
);

final shiftRepositoryProvider = Provider<ShiftRepository>(
  (ref) => ShiftRepository(ref.watch(apiClientProvider)),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

final ratingsRepositoryProvider = Provider<RatingsRepository>(
  (ref) => RatingsRepository(ref.watch(apiClientProvider)),
);

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(ref.watch(apiClientProvider), ref.watch(firebaseStorageProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);

final adminTrainingRepositoryProvider = Provider<AdminTrainingRepository>(
  (ref) => AdminTrainingRepository(ref.watch(apiClientProvider)),
);

/// Admin view of the modules, answer key included. Separate from
/// [trainingOverviewProvider] because that one is the practitioner's view with
/// the answers stripped — an edit has to invalidate both.
final adminTrainingModulesProvider =
    FutureProvider.autoDispose<List<AdminTrainingModule>>(
  (ref) => ref.watch(adminTrainingRepositoryProvider).list(),
);

final trainingRepositoryProvider = Provider<TrainingRepository>(
  (ref) => TrainingRepository(ref.watch(apiClientProvider), ref.watch(firebaseStorageProvider)),
);

/// The practitioner's training modules plus their own progress. Watched by the
/// training tab and by the profile badge, so completing a quiz refreshes both.
final trainingOverviewProvider = FutureProvider.autoDispose<TrainingOverview>(
  (ref) => ref.watch(trainingRepositoryProvider).list(),
);

/// The single source of truth for "who is signed in" throughout the app.
///
/// router.dart's redirect logic waits for this to have a value before it
/// will leave the splash route — if `authStateChanges()` never emits (a
/// stuck/corrupted native persisted-session restore, seen in practice after
/// installing over an existing app several times with new Firebase SDKs
/// added), the app was stuck on splash *before ever reaching* the
/// isAdminProvider/ownProfileProvider timeouts below, since the redirect
/// returns early on `!authState.hasValue`. Falling back to "signed out"
/// after a timeout, rather than leaving this pending forever, closes that
/// gap: worst case a real session takes an extra beat to restore and the
/// user has to sign in again, instead of never getting past splash at all.
///
/// This only guards the *first* event: `Stream.timeout()` restarts its
/// clock after every event it sees, including ones this callback itself
/// declines to emit — a naive version of this fired repeatedly during any
/// long quiet stretch (normal once someone's actually signed in, since
/// nothing further changes auth state) and injected a spurious "signed
/// out" partway through a real session, bouncing the user back to the
/// sign-in screen. `_sawFirstEvent` makes the fallback a one-shot: once a
/// real event has come through, later timeout ticks are no-ops.
final authStateProvider = StreamProvider<User?>((ref) {
  var sawFirstEvent = false;
  return ref
      .watch(authRepositoryProvider)
      .authStateChanges
      .timeout(
        const Duration(seconds: 10),
        onTimeout: (sink) {
          if (!sawFirstEvent) sink.add(null);
        },
      )
      .map((user) {
        sawFirstEvent = true;
        return user;
      });
});

/// The signed-in user's own profile (role, dbsStatus, rating). Fetched over
/// plain HTTP rather than a live Firestore stream — see
/// shift_repository.dart's fetchOpenShifts doc comment for why. Callers
/// that mutate the profile (setRole, updateProfile) must
/// `ref.invalidate(ownProfileProvider)` afterwards to see the change,
/// since there's no push update anymore.
final ownProfileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  return ref.watch(profileRepositoryProvider).fetchOwnProfile(
        fallbackUid: user.uid,
        fallbackName: user.displayName,
      );
});

final publicProfileProvider = FutureProvider.autoDispose.family<PublicProfile?, String>((ref, String uid) {
  return ref.watch(profileRepositoryProvider).fetchPublicProfile(uid);
});

/// True when the signed-in user carries the Firebase "admin" custom claim
/// (set out-of-band — see backend/services/core/function/documents.go
/// isAdmin — never through any endpoint in this codebase). Distinct from
/// [Profile.role]: an admin account has no nursery/staff role at all, so the
/// router checks this before falling into the normal role-select/onboarding
/// gate (router.dart).
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return false;
  // Bounded and defaulted to false on failure/timeout — this sits on the
  // splash → app redirect path (router.dart), so a stalled network call
  // here used to strand the user on splash forever with no way out.
  try {
    final result = await user.getIdTokenResult().timeout(const Duration(seconds: 10));
    return result.claims?['admin'] == true;
  } catch (_) {
    return false;
  }
});
