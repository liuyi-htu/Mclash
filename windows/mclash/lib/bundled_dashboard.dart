import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Resources are pinned in the app; the core serves them on its local /ui/ URL.
Future<void> installBundledDashboard(
  Directory directory, {
  Future<ByteData> Function(String)? load,
}) async {
  final read = load ?? rootBundle.load;
  final manifestData = await read('assets/dashboard/bundle.json');
  final manifestBytes = manifestData.buffer.asUint8List(
    manifestData.offsetInBytes,
    manifestData.lengthInBytes,
  );
  final manifest = utf8.decode(manifestBytes);
  final marker = File('${directory.path}${Platform.pathSeparator}bundle.json');
  final index = File('${directory.path}${Platform.pathSeparator}index.html');
  if (await marker.exists() &&
      await index.exists() &&
      await marker.readAsString() == manifest) {
    return;
  }
  final document = jsonDecode(manifest) as Map<String, dynamic>;
  for (final entry in document['files'] as List<dynamic>) {
    final path = entry as String;
    if (path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((part) => part == '..' || part.isEmpty) ||
        path.contains(':')) {
      throw const FormatException('本地面板资源路径无效');
    }
    final data = await read('assets/dashboard/$path');
    final target = File('${directory.path}${Platform.pathSeparator}$path');
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(
        data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
        flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
  if (await marker.exists()) {
    final previous =
        jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
    for (final path in previous['files'] as List<dynamic>) {
      if (path is! String || (document['files'] as List).contains(path)) {
        continue;
      }
      if (path.startsWith('/') ||
          path.contains('\\') ||
          path.contains(':') ||
          path.split('/').any((part) => part == '..' || part.isEmpty)) {
        continue;
      }
      final obsolete = File('${directory.path}${Platform.pathSeparator}$path');
      if (await obsolete.exists()) await obsolete.delete();
    }
  }
  await marker.writeAsString(manifest, flush: true);
}
