import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'flavor.dart';

class UpdateInfo {
  final int buildNumber;
  final String versionName;
  final String apkUrl;
  const UpdateInfo({required this.buildNumber, required this.versionName, required this.apkUrl});
}

/// Polls the version manifest published alongside each release's APKs (see
/// .github/workflows/build-flutter-apps.yml's "Publish APKs to website
/// downloads" step) and compares its buildNumber — the same
/// `--build-number=$run_number` every flutter build apk command in that
/// workflow run used, so it's already one shared, always-ascending
/// sequence across all three flavors — against the installed app's own
/// PackageInfo.buildNumber. A non-null result means a newer build than
/// what's installed has actually been published.
class UpdateChecker {
  static const _manifestUrl = 'https://wslha.co/downloads/version.json';

  Future<UpdateInfo?> checkForUpdate(AppFlavor flavor) async {
    try {
      final res = await http
          .get(Uri.parse('$_manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final latestBuild = (data['buildNumber'] as num?)?.toInt();
      if (latestBuild == null) return null;

      final info = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(info.buildNumber) ?? 0;
      if (latestBuild <= installedBuild) return null;

      final flavorName = switch (flavor) {
        AppFlavor.customer => 'customer',
        AppFlavor.driver => 'driver',
        AppFlavor.merchant => 'merchant',
      };
      return UpdateInfo(
        buildNumber: latestBuild,
        versionName: data['versionName'] as String? ?? '',
        apkUrl: 'https://wslha.co/downloads/wslha-$flavorName.apk',
      );
    } catch (_) {
      // No connection, manifest not published yet, malformed JSON — treat
      // all the same as "nothing to report", never block/interrupt the app.
      return null;
    }
  }
}
