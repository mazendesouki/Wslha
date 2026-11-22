import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Thrown when the download itself fails (bad HTTP status, i/o error) —
/// distinct from an install-trigger failure so callers can show the right
/// message for each ("couldn't download" vs "couldn't open the installer").
class ApkDownloadException implements Exception {
  final String message;
  ApkDownloadException(this.message);
  @override
  String toString() => message;
}

class ApkInstallException implements Exception {
  final String message;
  ApkInstallException(this.message);
  @override
  String toString() => message;
}

/// Downloads [apkUrl] to local storage (reporting 0.0–1.0 progress via
/// [onProgress], or null if the server didn't send a content-length) and
/// then hands the finished file to Android's own package installer via
/// open_filex — it resolves a content:// URI through its own bundled
/// FileProvider, so nothing extra needs declaring on this app's side
/// beyond the REQUEST_INSTALL_PACKAGES permission in AndroidManifest.xml.
///
/// This is the in-app replacement for launchUrl()-ing the APK straight
/// into the browser and leaving the user to find and open the download
/// themselves. Android still requires an explicit user tap on its own
/// install-confirmation screen either way — no app, including this one,
/// can silently install an update over itself; that's an OS security
/// boundary this can't and shouldn't try to bypass. What changes is that
/// the download + the handoff into that install screen both happen
/// in-app instead of needing a trip through the browser and Downloads.
Future<void> downloadAndInstallApk(
  String apkUrl, {
  required void Function(double? progress) onProgress,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/wslha-update.apk');

  final http.StreamedResponse response;
  try {
    response = await http.Client().send(http.Request('GET', Uri.parse(apkUrl)));
  } catch (e) {
    throw ApkDownloadException('$e');
  }
  if (response.statusCode != 200) {
    throw ApkDownloadException('http_${response.statusCode}');
  }

  final total = response.contentLength;
  var received = 0;
  final sink = file.openWrite();
  try {
    await response.stream.listen((chunk) {
      sink.add(chunk);
      received += chunk.length;
      if (total != null && total > 0) onProgress(received / total);
    }).asFuture<void>();
  } catch (e) {
    throw ApkDownloadException('$e');
  } finally {
    await sink.close();
  }

  final result = await OpenFilex.open(file.path);
  if (result.type != ResultType.done) {
    throw ApkInstallException('${result.type}: ${result.message}');
  }
}
