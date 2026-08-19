import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/constants/legal_links.dart';
import 'delete_account_flow.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    setState(() => _deleting = true);
    try {
      await confirmAndDeleteAccount(context, ref);
      // On success the router redirects to /sign-in once auth state clears;
      // on cancellation or failure the flow has already told the user why.
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final authRepo = ref.watch(authRepositoryProvider);
    final email = authRepo.currentUser?.email ?? '';
    final hasPassword = authRepo.hasPasswordProvider;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _SectionLabel('ACCOUNT'),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.mail_outline_rounded),
                    title: const Text('Email'),
                    subtitle: Text(email.isEmpty ? 'Unknown' : email),
                  ),
                  if (hasPassword) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_outline_rounded),
                      title: const Text('Change password'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/settings/change-password'),
                    ),
                  ] else ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text('Signed in with ${authRepo.hasAppleProvider ? 'Apple' : 'Google'}'),
                      subtitle: Text(
                        'Manage this login from your '
                        '${authRepo.hasAppleProvider ? 'Apple ID' : 'Google account'}.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel('LEGAL & SUPPORT'),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  _LinkTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & support',
                    url: LegalLinks.support,
                  ),
                  const Divider(height: 1),
                  _LinkTile(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    url: LegalLinks.terms,
                  ),
                  const Divider(height: 1),
                  _LinkTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    url: LegalLinks.privacy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionLabel('DANGER ZONE'),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              color: scheme.error.withValues(alpha: 0.06),
              child: ListTile(
                leading: Icon(Icons.delete_forever_rounded, color: scheme.error),
                title: Text('Delete account', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700)),
                subtitle: const Text('Permanently erase your profile, documents and login.'),
                trailing: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _deleting ? null : _confirmDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
      );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.url});

  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
}
