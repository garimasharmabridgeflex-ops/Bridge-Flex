import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password updated.')));
        context.pop();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyChangePasswordError(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Current password',
                  controller: _current,
                  obscureText: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'New password',
                  controller: _next,
                  obscureText: true,
                  prefixIcon: Icons.lock_reset_rounded,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'At least 6 characters' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Confirm new password',
                  controller: _confirm,
                  obscureText: true,
                  prefixIcon: Icons.lock_reset_rounded,
                  textInputAction: TextInputAction.done,
                  validator: (v) =>
                      (v != _next.text) ? 'Passwords do not match' : null,
                ),
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
                  label: 'Update password',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyChangePasswordError(String code) => switch (code) {
      'wrong-password' || 'invalid-credential' => 'Your current password is incorrect.',
      'weak-password' => 'Choose a stronger new password.',
      'requires-recent-login' => 'Please sign out and back in, then try again.',
      'too-many-requests' => 'Too many attempts — try again shortly.',
      _ => 'Something went wrong. Please try again.',
    };
