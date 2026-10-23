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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: Color(0xFF2563EB), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'A new version of KFlex is available.',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF1E40AF)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _openDownloadUrl(downloadUrl),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF2563EB))),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF2563EB)),
            ),
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
          'This version of KFlex is no longer supported. Please download the latest '
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
