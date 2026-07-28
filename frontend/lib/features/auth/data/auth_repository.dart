import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/env.dart';

/// The project's Web OAuth client (client_type 3 in google-services.json) —
/// not a secret (see CONFIG_AND_KEYS.md), just the audience Firebase expects
/// the Google ID token to be issued for. Passed as `serverClientId` so
/// Android's native picker returns a token Firebase can actually verify.
const _googleWebClientId =
    '288297326448-k8d6as8g4ouv4iur0romitcffg1sq5o9.apps.googleusercontent.com';

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  bool _googleSignInInitialized = false;

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
    unawaited(_ensureProfileDocument(credential.user!.uid, name));
    unawaited(_sendVerificationEmailBestEffort(credential.user));
  }

  /// "Sign in with Google". Two different flows depending on target:
  ///
  /// - **Local dev** (`Env.useLocalBackend`, against `demo-bridgeflex`):
  ///   Firebase Auth's built-in generic-provider flow (`signInWithProvider`).
  ///   No real Google OAuth client exists for the demo project, but the Auth
  ///   emulator fakes an identity picker for this flow with zero setup.
  /// - **Real builds**: the native `google_sign_in` plugin, which drives
  ///   Android's Credential Manager account picker / iOS's native sheet —
  ///   the platform-native experience users expect, rather than
  ///   `signInWithProvider`'s browser-redirect flow (which technically works
  ///   against a real project, but opens a Custom Tab instead of a native
  ///   picker — not what "Sign in with Google" normally looks like).
  Future<void> signInWithGoogle() async {
    final User? user;
    if (Env.useLocalBackend) {
      final credential = await _auth.signInWithProvider(GoogleAuthProvider());
      user = credential.user;
    } else {
      user = await _signInWithGoogleNative();
    }
    if (user != null) {
      await _ensureProfileDocument(user.uid, user.displayName ?? '');
      unawaited(_syncGooglePhotoIfUnset(user.uid, user.photoURL));
    }
  }

  Future<User?> _signInWithGoogleNative() async {
    final googleSignIn = GoogleSignIn.instance;
    if (!_googleSignInInitialized) {
      await googleSignIn.initialize(serverClientId: _googleWebClientId);
      _googleSignInInitialized = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }

    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final userCredential = await _auth.signInWithCredential(credential);
    return userCredential.user;
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

  /// Fills the app profile's photo from the signed-in Google account —
  /// *only* while the profile has no photo of its own. Runs on every Google
  /// sign-in (not just the first), so a user who never uploaded a custom
  /// photo keeps picking up their current Gmail avatar, but the moment
  /// they set one in-app, this stops touching the field permanently.
  Future<void> _syncGooglePhotoIfUnset(String uid, String? googlePhotoUrl) async {
    if (googlePhotoUrl == null || googlePhotoUrl.isEmpty) return;
    try {
      await Future(() async {
        final ref = _firestore.collection('profiles').doc(uid);
        final snap = await ref.get();
        final existingPhoto = snap.data()?['photoUrl'] as String?;
        if (existingPhoto != null && existingPhoto.isNotEmpty) return;
        await ref.set({'photoUrl': googlePhotoUrl}, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort — same rationale as _ensureProfileDocument above.
    }
  }

  /// Firebase Auth's built-in password-reset email — same "no SMTP setup
  /// needed" story as [_sendVerificationEmailBestEffort]. Unlike that one,
  /// failures here must surface to the caller (wrong/unknown email, rate
  /// limiting) so the UI can tell the user what happened.
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  /// True for an email/password account. A Google-only sign-in has no
  /// password provider attached, so "change password" doesn't apply to it —
  /// callers use this to hide that option instead of surfacing a confusing
  /// "wrong current password" error for every attempt.
  bool get hasPasswordProvider =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;

  /// Firebase requires a "recent login" before a sensitive update like this
  /// succeeds, so this re-proves identity with the current password first
  /// rather than relying on however old the existing session happens to be.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('No signed-in email/password user.');
    }
    final credential = EmailAuthProvider.credential(email: email, password: currentPassword);
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Re-fetches the user record from Auth so a just-clicked verification
  /// link is reflected in `currentUser.emailVerified` without a full
  /// sign-out/sign-in — call before reading [User.emailVerified] for display.
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    await user.sendEmailVerification();
  }

  Future<void> signOut() => _auth.signOut();
}
