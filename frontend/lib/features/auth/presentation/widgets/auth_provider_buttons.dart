import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme.dart';
import '../../../../shared/constants/legal_links.dart';

/// The "or" divider plus every third-party login KFlex offers, shared by the
/// sign-in and sign-up screens so the two can never drift apart.
///
/// Apple and Google both create an account on first use, so this is the same
/// widget in both places — only the surrounding copy differs.
class AuthProviderButtons extends ConsumerStatefulWidget {
  const AuthProviderButtons({super.key, required this.onError});

  /// Called with a human-readable message on failure, or null to clear a
  /// previously shown error when a fresh attempt starts.
  final ValueChanged<String?> onError;

  @override
  ConsumerState<AuthProviderButtons> createState() => _AuthProviderButtonsState();
}

class _AuthProviderButtonsState extends ConsumerState<AuthProviderButtons> {
  bool _appleLoading = false;
  bool _googleLoading = false;

  bool get _busy => _appleLoading || _googleLoading;

  Future<void> _run(Future<void> Function() action, void Function(bool) setLoading) async {
    widget.onError(null);
    setState(() => setLoading(true));
    try {
      await action();
      // Navigation happens on its own via authStateProvider + router redirect.
    } on FirebaseAuthException catch (e) {
      widget.onError(_friendlyProviderError(e.code));
    } on SignInWithAppleNotSupportedException {
      widget.onError('Sign in with Apple needs iOS 13 or later.');
    } on SignInWithAppleException {
      widget.onError("Couldn't complete Sign in with Apple. Please try again.");
    } catch (_) {
      // Most commonly the user dismissing the provider sheet — the repository
      // already turns a real cancellation into a no-op, so anything reaching
      // here is not worth interrupting them over.
    } finally {
      if (mounted) setState(() => setLoading(false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.read(authRepositoryProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: scheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
            Expanded(child: Divider(color: scheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (auth.appleSignInSupported) ...[
          // Apple's own button widget rather than a hand-rolled one: guideline
          // 4.8 review checks the mark, wording and proportions, and this
          // renders them to Apple's spec. White-on-dark / black-on-light keeps
          // the required contrast in both themes.
          SignInWithAppleButton(
            text: _appleLoading ? 'Signing in…' : 'Continue with Apple',
            height: 48,
            borderRadius: BorderRadius.circular(AppRadius.md),
            style: isDark
                ? SignInWithAppleButtonStyle.white
                : SignInWithAppleButtonStyle.black,
            onPressed: _busy
                ? () {}
                : () => _run(auth.signInWithApple, (v) => _appleLoading = v),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(auth.signInWithGoogle, (v) => _googleLoading = v),
          icon: _googleLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Image.asset('assets/branding/google_logo.png', width: 18, height: 18),
          label: const Text('Continue with Google'),
        ),
      ],
    );
  }
}

/// The line every account-creating screen needs: what the user is agreeing to,
/// with the two documents one tap away rather than only reachable from the
/// website.
///
/// Stateful purely so the tap recognizers can be disposed — a
/// [TapGestureRecognizer] built inside `build` is never released and leaks on
/// every rebuild.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({super.key, this.action = 'continuing'});

  /// Slots into "By {action} you agree to…" — e.g. 'creating an account'.
  final String action;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()..onTap = () => _open(LegalLinks.terms);
    _privacy = TapGestureRecognizer()..onTap = () => _open(LegalLinks.privacy);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger?.showSnackBar(SnackBar(content: Text("Couldn't open $url")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45);
    final link = base?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: 'By ${widget.action} you agree to our '),
          TextSpan(text: 'Terms of Service', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

String _friendlyProviderError(String code) => switch (code) {
      'account-exists-with-different-credential' =>
        'You already have an account with that email — sign in the way you did last time.',
      'invalid-credential' => "That sign-in couldn't be verified. Please try again.",
      'user-disabled' => 'That account has been suspended.',
      'network-request-failed' => 'No connection — check your network and try again.',
      _ => 'Something went wrong. Please try again.',
    };
