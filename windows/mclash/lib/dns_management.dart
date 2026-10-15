import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'dialog_typography.dart';
import 'management_style.dart';

const managedDnsKeys = {'ipv6'};

Object? _plain(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries) _plain(entry.key): _plain(entry.value)
    };
  }
  if (value is List) return [for (final item in value) _plain(item)];
  return value;
}

String configDnsText(String content) {
  final document = loadYaml(content);
  if (document is! YamlMap) throw const FormatException('配置必须是 YAML 映射');
  final dns = document['dns'];
  if (dns == null) return '{}\n';
  if (dns is! YamlMap) throw const FormatException('DNS 配置必须是 YAML 映射');
  final editable = {
    for (final entry in dns.entries)
      if (!managedDnsKeys.contains(entry.key)) entry.key: _plain(entry.value)
  };
  return '${YamlEditor('{}')..update([], editable)}\n';
}

String updateConfigDns(String content, String text) {
  final dns = loadYaml(text);
  if (dns is! YamlMap) {
    throw const FormatException('DNS 配置必须是 YAML 映射，例如 nameserver: [1.1.1.1]');
  }
  final document = loadYaml(content);
  if (document is! YamlMap) throw const FormatException('配置必须是 YAML 映射');
  final previous = document['dns'];
  final merged = {
    if (previous is YamlMap)
      for (final entry in previous.entries)
        if (managedDnsKeys.contains(entry.key)) entry.key: _plain(entry.value),
    for (final entry in dns.entries)
      if (!managedDnsKeys.contains(entry.key)) entry.key: _plain(entry.value),
  };
  return (YamlEditor(content)..update(['dns'], merged)).toString();
}

Future<bool> showDnsManagementDialog({
  required BuildContext context,
  required String content,
  required Future<void> Function(String) onSave,
}) async {
  final controller = TextEditingController(text: configDnsText(content));
  bool saving = false;
  String? error;
  try {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => PopScope(
              canPop: !saving,
              child: DialogTypography(
                  child: AlertDialog(
                scrollable: true,
                title: const Text('DNS 管理'),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: (MediaQuery.sizeOf(context).height * 0.5)
                            .clamp(120.0, 420.0),
                        child: TextField(
                          controller: controller,
                          enabled: !saving,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13),
                          decoration: managementFieldDecoration(
                              context, 'DNS 配置（YAML）'),
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            update(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              // Validate before calling the persistence layer.
                              updateConfigDns(content, controller.text);
                              await onSave(controller.text);
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (failure) {
                              if (context.mounted) {
                                update(() {
                                  saving = false;
                                  error = failure.toString();
                                });
                              }
                            }
                          },
                    child: Text(saving ? '保存中…' : '保存'),
                  ),
                ],
              )),
            ),
          ),
        ) ??
        false;
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }
}
