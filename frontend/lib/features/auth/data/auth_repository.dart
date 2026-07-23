import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(name);
    await _ensureProfileDocument(credential.user!.uid, name);
    // Best-effort — Firebase Auth sends this itself, no SMTP/backend config
    // needed. See sendEmailVerification doc comment below for why this is
    // never awaited-and-surfaced as a hard failure.
    unawaited(_sendVerificationEmailBestEffort(credential.user));
  }

  /// "Sign in with Google" via Firebase Auth's built-in provider flow
  /// (not the separate `google_sign_in` package) — deliberately, since this
  /// project currently runs against a `demo-*` Firebase project
  /// (firebase_options.dart) with no real Google OAuth client configured.
  /// `signInWithProvider` is Auth-emulator-aware and shows a fake identity
  /// picker locally with zero extra setup; swapping in a real Firebase
  /// project later (and registering OAuth clients / SHA-1 fingerprints in
  /// its console) makes this start working for real with no code change.
  Future<void> signInWithGoogle() async {
    final credential = await _auth.signInWithProvider(GoogleAuthProvider());
    final user = credential.user;
    if (user != null) {
      await _ensureProfileDocument(user.uid, user.displayName ?? '');
    }
  }

  /// Firebase Auth's own "verify your email" send — full app spec: "the app
  /// should send emails once people have registered". Requires no SMTP/mail
  /// provider configuration since Firebase delivers it directly; the
  /// tradeoff is the template/sender can't be customized beyond what the
  /// Firebase/GCP console's Auth templates page allows.
  Future<void> _sendVerificationEmailBestEffort(User? user) async {
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } catch (_) {
      // Best-effort — a failed verification email must never block sign-up.
    }
  }

  /// In production `initProfileOnSignUp` (an Eventarc Auth trigger) creates
  /// this doc server-side. That trigger has no local emulator dispatch story
  /// (ARCHITECTURE.md v2 §1a/§7), so local sign-up would otherwise leave the
  /// caller with no profiles/{uid} doc at all. Security Rules already permit
  /// `allow create: if isOwner(uid)`, so creating the identical
  /// server-shaped doc client-side is a legal, harmless no-op once the real
  /// trigger fires (same fields, trigger's write just wins the race).
  ///
  /// This is a direct Firestore SDK call (gRPC), unlike the rest of this
  /// app's reads/writes which go through plain-HTTP Cloud Function
  /// endpoints — there's no HTTP equivalent for "create my own profile" to
  /// fall back to. On networks where gRPC to the emulator can't complete
  /// (see shift_repository.dart's fetchOpenShifts note), this silently times
  /// out rather than hanging sign-up forever; the account still exists in
  /// Auth, but role-select will find no profile doc until this succeeds.
  Future<void> _ensureProfileDocument(String uid, String name) async {
    try {
      await Future(() async {
        final ref = _firestore.collection('profiles').doc(uid);
        final snap = await ref.get();
        if (snap.exists) return;
        await ref.set({
          'role': '',
          'name': name,
          'dbsStatus': 'unverified',
          'rating': {'average': 0, 'count': 0},
          'createdAt': FieldValue.serverTimestamp(),
        });
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }

  Future<void> signOut() => _auth.signOut();
}
