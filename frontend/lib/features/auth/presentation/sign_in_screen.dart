import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/app_brand_mark.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../app/providers.dart';
import 'widgets/auth_provider_buttons.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _email.text.trim(),
            password: _password.text,
          );
      // Navigation happens automatically via authStateProvider + router redirect.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xxl),
                    const AppBrandMark(withWordmark: true)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.15, end: 0),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Welcome back',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to find or fill your next shift.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      label: 'Email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.mail_outline_rounded,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ).animate().fadeIn(delay: 200.ms, duration: 350.ms).slideX(begin: 0.05, end: 0),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Password',
                      controller: _password,
                      obscureText: true,
                      prefixIcon: Icons.lock_outline_rounded,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    ).animate().fadeIn(delay: 250.ms, duration: 350.ms).slideX(begin: 0.05, end: 0),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push('/forgot-password'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ).animate().fadeIn(delay: 270.ms, duration: 350.ms),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _error == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _error!,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Sign in',
                      loading: _loading,
                      onPressed: _submit,
                    ).animate().fadeIn(delay: 300.ms, duration: 350.ms),
                    const SizedBox(height: AppSpacing.md),
                    AuthProviderButtons(
                      onError: (message) => setState(() => _error = message),
                    ).animate().fadeIn(delay: 320.ms, duration: 350.ms),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: TextButton(
                        onPressed: () => context.push('/sign-up'),
                        child: const Text("Don't have an account? Sign up"),
                      ),
                    ).animate().fadeIn(delay: 350.ms, duration: 350.ms),
                    const SizedBox(height: AppSpacing.sm),
                    // Apple and Google both create an account on first use, so
                    // this belongs on the sign-in screen too, not only sign-up.
                    const LegalConsentText(action: 'continuing')
                        .animate()
                        .fadeIn(delay: 380.ms, duration: 350.ms),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyAuthError(String code) => switch (code) {
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        'Incorrect email or password.',
      'invalid-email' => 'That email address looks invalid.',
      'too-many-requests' => 'Too many attempts — try again shortly.',
      _ => 'Something went wrong. Please try again.',
    };
