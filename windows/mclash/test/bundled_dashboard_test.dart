import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/bundled_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline bundle contains every declared resource', () async {
    final directory =
        await Directory.systemTemp.createTemp('dashboard-bundle-');
    try {
      await installBundledDashboard(directory);
      final manifest = jsonDecode(
          await File('${directory.path}/bundle.json').readAsString());
      for (final path in manifest['files'] as List) {
        expect(await File('${directory.path}/$path').length(), greaterThan(0),
            reason: path);
      }
      expect(await File('${directory.path}/config.js').readAsString(),
          contains('window.location.origin'));
      await installBundledDashboard(directory);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('failed extraction retries and upgrade replaces files', () async {
    final directory =
        await Directory.systemTemp.createTemp('dashboard-bundle-');
    var revision = 'one';
    var interrupted = true;
    Future<ByteData> read(String path) async {
      if (path.endsWith('bundle.json')) {
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
          'revision': revision,
          'files': ['index.html', '_nuxt/app.js'],
        }))));
      }
      if (interrupted && path.endsWith('app.js')) {
        throw StateError('interrupted');
      }
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(revision)));
    }

    try {
      await expectLater(
          installBundledDashboard(directory, load: read), throwsStateError);
      expect(await File('${directory.path}/bundle.json').exists(), isFalse);
      interrupted = false;
      await installBundledDashboard(directory, load: read);
      revision = 'two';
      await installBundledDashboard(directory, load: read);
      expect(
          await File('${directory.path}/_nuxt/app.js').readAsString(), 'two');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
