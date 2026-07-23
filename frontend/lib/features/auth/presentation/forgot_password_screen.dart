import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyResetError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sent ? _buildSentState(scheme) : _buildFormState(scheme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormState(ColorScheme scheme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.lg),
          Icon(Icons.lock_reset_rounded, size: 56, color: scheme.primary)
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Forgot your password?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ).animate().fadeIn(delay: 100.ms, duration: 350.ms),
          const SizedBox(height: 6),
          Text(
            "Enter the email on your account and we'll send you a link to reset it.",
            style: TextStyle(color: scheme.onSurfaceVariant),
          ).animate().fadeIn(delay: 150.ms, duration: 350.ms),
          const SizedBox(height: AppSpacing.xl),
          AppTextField(
            label: 'Email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.mail_outline_rounded,
            textInputAction: TextInputAction.done,
            autofocus: true,
            validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ).animate().fadeIn(delay: 200.ms, duration: 350.ms),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Send reset link',
            loading: _loading,
            onPressed: _submit,
          ).animate().fadeIn(delay: 250.ms, duration: 350.ms),
        ],
      ),
    );
  }

  Widget _buildSentState(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(Icons.mark_email_read_rounded, size: 56, color: AppColors.mint)
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Check your inbox',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ).animate().fadeIn(delay: 100.ms, duration: 350.ms),
        const SizedBox(height: 6),
        Text(
          "We've sent a password reset link to ${_email.text.trim()}. "
          "Follow the link to choose a new password, then come back and sign in.",
          style: TextStyle(color: scheme.onSurfaceVariant),
        ).animate().fadeIn(delay: 150.ms, duration: 350.ms),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Back to sign in',
          onPressed: () => context.pop(),
        ).animate().fadeIn(delay: 200.ms, duration: 350.ms),
      ],
    );
  }
}

String _friendlyResetError(String code) => switch (code) {
      'user-not-found' => 'No account found for that email.',
      'invalid-email' => 'That email address looks invalid.',
      'too-many-requests' => 'Too many attempts — try again shortly.',
      _ => 'Something went wrong. Please try again.',
    };
