import 'package:url_launcher/url_launcher.dart';

class ExternalAppLauncher {
  static Future<bool> launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> launchFirst(Iterable<Uri> uris) async {
    for (final uri in uris) {
      if (await launch(uri)) {
        return true;
      }
    }
    return false;
  }
}
