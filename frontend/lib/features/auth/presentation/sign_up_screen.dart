import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/app_brand_mark.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
      await ref.read(authRepositoryProvider).signUp(
            email: _email.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
          );
      // Router redirect takes the new user to role selection automatically.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // Router redirect takes the new user to role selection automatically.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code));
    } catch (_) {
      // User closed the provider popup/sheet — not an error worth surfacing.
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
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
                    const AppBrandMark(withWordmark: true)
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.15, end: 0),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Create your account',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ).animate().fadeIn(duration: 350.ms),
                    const SizedBox(height: 6),
                    Text(
                      "You'll choose nursery or staff next.",
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ).animate().fadeIn(delay: 60.ms, duration: 350.ms),
                    const SizedBox(height: AppSpacing.xl),
                    AppTextField(
                      label: 'Full name',
                      controller: _name,
                      prefixIcon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                    ).animate().fadeIn(delay: 100.ms, duration: 300.ms).slideX(begin: 0.05, end: 0),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.mail_outline_rounded,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ).animate().fadeIn(delay: 150.ms, duration: 300.ms).slideX(begin: 0.05, end: 0),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Password',
                      controller: _password,
                      obscureText: true,
                      prefixIcon: Icons.lock_outline_rounded,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    ).animate().fadeIn(delay: 200.ms, duration: 300.ms).slideX(begin: 0.05, end: 0),
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
                      label: 'Create account',
                      loading: _loading,
                      onPressed: _submit,
                    ).animate().fadeIn(delay: 250.ms, duration: 300.ms),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ),
                        Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _googleLoading ? null : _submitGoogle,
                      icon: _googleLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.g_mobiledata_rounded, size: 26),
                      label: const Text('Continue with Google'),
                    ).animate().fadeIn(delay: 280.ms, duration: 300.ms),
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
      'email-already-in-use' => 'An account already exists for that email.',
      'invalid-email' => 'That email address looks invalid.',
      'weak-password' => 'Choose a stronger password.',
      _ => 'Something went wrong. Please try again.',
    };
