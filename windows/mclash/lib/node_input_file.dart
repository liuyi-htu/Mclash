import 'dart:convert';
import 'dart:io';
import 'mihomo_node_input.dart';

Future<String?> pickNodeInputFile() async {
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = 'Mihomo YAML (*.yaml;*.yml;*.txt)|*.yaml;*.yml;*.txt|All files (*.*)|*.*'
try {
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    [Console]::Out.WriteLine($dialog.FileName)
  }
} finally { $dialog.Dispose() }
''';
  final result = await Process.run(
      'powershell.exe', ['-NoProfile', '-STA', '-Command', script],
      stdoutEncoding: utf8);
  if (result.exitCode != 0) throw const FileSystemException('无法打开节点文件选择器');
  final path = (result.stdout as String).trim();
  if (path.isEmpty) return null;
  try {
    final bytes = <int>[];
    await for (final chunk in File(path).openRead()) {
      if (bytes.length + chunk.length > maxNodeInputBytes) {
        throw const FormatException('节点文件过大（最多 8 MiB）');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  } on FileSystemException {
    throw const FileSystemException('无法读取节点文件');
  }
}
