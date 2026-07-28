import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// There was previously no way to tell users a new version exists — once
/// installed, the app never checked again. This closes that gap using
/// Firebase Remote Config as the "what's the latest version" source of
/// truth, so publishing a new release doesn't require any backend redeploy
/// — just updating three Remote Config values in the Firebase Console (or
/// via its REST API): `latest_version_code`, `min_supported_version_code`,
/// `download_url`.
enum AppUpdateStatus {
  /// Installed build is current — nothing to show.
  none,

  /// A newer build exists. Dismissible nudge, not a blocker.
  optional,

  /// Installed build is below `min_supported_version_code` — the app should
  /// prompt to update before continuing. Defaults to never firing (the
  /// fallback `min_supported_version_code` below is 1, i.e. everyone is
  /// "supported") unless explicitly raised in Remote Config.
  required,
}

class AppUpdateInfo {
  const AppUpdateInfo(this.status, this.downloadUrl);
  final AppUpdateStatus status;
  final String downloadUrl;
}

const _defaultDownloadUrl = 'https://kvision-503115.web.app';

/// Fetch/activate is wrapped in try/catch throughout — a failed or slow
/// Remote Config fetch (offline, first-run throttling, etc.) must never
/// block or crash the app. Worst case: it silently falls back to "no
/// update available," same as if this feature didn't exist.
final appUpdateStatusProvider = FutureProvider<AppUpdateInfo>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final installedBuild = int.tryParse(info.buildNumber) ?? 0;

    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await remoteConfig.setDefaults({
      'latest_version_code': installedBuild,
      'min_supported_version_code': 1,
      'download_url': _defaultDownloadUrl,
    });

    try {
      await remoteConfig.fetchAndActivate();
    } catch (e) {
      // Offline / throttled / first-run — fall through and use whatever
      // defaults/cached values are already set above.
      debugPrint('Remote Config fetch skipped: $e');
    }

    final latest = remoteConfig.getInt('latest_version_code');
    final minSupported = remoteConfig.getInt('min_supported_version_code');
    final downloadUrl = remoteConfig.getString('download_url');
    final url = downloadUrl.isEmpty ? _defaultDownloadUrl : downloadUrl;

    if (installedBuild < minSupported) return AppUpdateInfo(AppUpdateStatus.required, url);
    if (installedBuild < latest) return AppUpdateInfo(AppUpdateStatus.optional, url);
    return AppUpdateInfo(AppUpdateStatus.none, url);
  } catch (e) {
    debugPrint('App update check skipped: $e');
    return const AppUpdateInfo(AppUpdateStatus.none, _defaultDownloadUrl);
  }
});
