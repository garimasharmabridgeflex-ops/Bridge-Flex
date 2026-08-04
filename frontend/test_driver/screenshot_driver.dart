// Driver half of the App Store screenshot capture (see
// integration_test/screenshots_test.dart). The test calls
// binding.takeScreenshot(name); the bytes arrive here, on the host, and get
// written to screenshots/<name>.png for the CI job to collect.
//
// integration_test_driver_extended is the variant that exposes onScreenshot —
// the plain integration_test_driver does not.

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('wrote ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
