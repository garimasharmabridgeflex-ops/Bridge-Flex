import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';

Future<void> _openDownloadUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Dismissible (session-only, same pattern as [EmailVerificationBanner]) —
/// for AppUpdateStatus.optional. A newer build exists but this one still
/// works fine.
class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({super.key, required this.downloadUrl, required this.onDismiss});

  final String downloadUrl;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.mint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.system_update_rounded, color: AppColors.mint, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A new version of Bridge Flex is available.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _openDownloadUrl(downloadUrl),
                  child: Text(
                    'Download update →',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0);
  }
}

/// Non-dismissible — for AppUpdateStatus.required. Defaults to never firing
/// (see app_update_service.dart) unless min_supported_version_code is
/// deliberately raised in Remote Config, so this only ever appears when
/// someone has explicitly decided the installed build must not keep running.
Future<void> showRequiredUpdateDialog(BuildContext context, String downloadUrl) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_rounded, color: AppColors.indigo, size: 32),
        title: const Text('Update required'),
        content: const Text(
          'This version of Bridge Flex is no longer supported. Please download the latest '
          'version to keep using the app.',
        ),
        actions: [
          FilledButton(
            onPressed: () => _openDownloadUrl(downloadUrl),
            child: const Text('Update now'),
          ),
        ],
      ),
    ),
  );
}
