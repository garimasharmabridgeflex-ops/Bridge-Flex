import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_repository.dart';
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

/// The single source of truth for "who is signed in" throughout the app.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges,
);

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
  final result = await user.getIdTokenResult();
  return result.claims?['admin'] == true;
});
