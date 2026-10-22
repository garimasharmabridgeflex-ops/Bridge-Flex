import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/policy_repository.dart';

/// TermsAcceptanceSheet displays required policies that must be accepted
/// before continuing onboarding or accepting/posting shifts.
class TermsAcceptanceSheet extends ConsumerStatefulWidget {
  const TermsAcceptanceSheet({
    super.key,
    required this.role,
    required this.onAccepted,
  });

  final String role;
  final VoidCallback onAccepted;

  static Future<void> show(BuildContext context, {required String role, required VoidCallback onAccepted}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TermsAcceptanceSheet(role: role, onAccepted: onAccepted),
    );
  }

  @override
  ConsumerState<TermsAcceptanceSheet> createState() => _TermsAcceptanceSheetState();
}

class _TermsAcceptanceSheetState extends ConsumerState<TermsAcceptanceSheet> {
  List<RequiredPolicy>? _policies;
  final Set<String> _acceptedPolicyIds = {};
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(policyRepositoryProvider).fetchRequiredPolicies(role: widget.role);
    if (!mounted) return;
    setState(() {
      _policies = list;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_policies == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(policyRepositoryProvider).acceptPolicies(_policies!);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onAccepted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not record terms acceptance: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allChecked = _policies != null &&
        _policies!.isNotEmpty &&
        _acceptedPolicyIds.length == _policies!.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Terms & Policies',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Please review and accept our updated terms and policies to continue using K Flex.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_policies != null)
              ..._policies!.map((policy) {
                final checked = _acceptedPolicyIds.contains(policy.id);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  title: Text(
                    policy.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    policy.summary ?? 'Version ${policy.version}',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _acceptedPolicyIds.add(policy.id);
                      } else {
                        _acceptedPolicyIds.remove(policy.id);
                      }
                    });
                  },
                );
              }),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Accept and continue',
              expand: true,
              loading: _submitting,
              onPressed: allChecked ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
