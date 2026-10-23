import 'package:flutter/services.dart';

/// Reads a snippet without importing or replacing a whole configuration.
Future<String?> pickNodeInputFile() =>
    const MethodChannel('mclash/native').invokeMethod<String>('pickNodeFile');
