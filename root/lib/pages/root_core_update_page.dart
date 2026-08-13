import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class RootCoreUpdatePage extends StatefulWidget {
  const RootCoreUpdatePage({super.key});

  @override
  State<RootCoreUpdatePage> createState() => _RootCoreUpdatePageState();
}

class _RootCoreUpdatePageState extends State<RootCoreUpdatePage> {
  static const _manifestUrl =
      'https://api.github.com/repos/MetaCubeX/mihomo/releases/latest';
  final _service = NativeProxyService.instance;
  RootCoreVersion? _version;
  bool _checking = false;
  bool _updating = false;
  String _stage = '尚未检查';
  double? _progress;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _stage = '正在读取在线 manifest…';
    });
    try {
      final version = await _service.checkRootCoreVersion(_manifestUrl);
      if (!mounted) return;
      setState(() {
        _version = version;
        _stage = version.hasUpdate ? '发现新版本' : '当前已是最新版本';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _stage = '检查失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _update() async {
    final version = _version;
    if (version == null) return;
    setState(() {
      _updating = true;
      _stage = '正在下载并校验；代理会保持运行…';
      _progress = 0;
    });
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final status = await _service.getRootCoreUpdateStatus();
        if (!mounted) return;
        final stage = status['stage'] as String? ?? 'downloading';
        setState(() {
          _progress = (status['progress'] as num?)?.toDouble();
          _stage = switch (stage) {
            'downloading' => '正在下载内核…',
            'verifying' => '正在校验 SHA-256 和可执行性…',
            'replacing' => '正在停止代理并原子替换…',
            'restarting' => '正在恢复代理并进行健康检查…',
            'rolledBack' => '新内核不可用，已回滚',
            'cancelled' => '下载已取消，当前内核未改变',
            'failed' => '更新失败，当前内核已保留',
            'success' => '内核更新成功',
            _ => _stage,
          };
        });
      } catch (_) {
        // The update result will carry the authoritative error.
      }
    });
    try {
      final result = await _service.updateRootCore(version);
      if (!mounted) return;
      setState(() => _stage = result['message'] as String? ?? '更新完成');
      showTopSnackBar(context, SnackBar(content: Text(_stage)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _stage = '更新失败：$error');
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() {
          _updating = false;
          _progress = null;
        });
      }
    }
  }

  String _size(int bytes) =>
      bytes < 0 ? '未知' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';

  @override
  Widget build(BuildContext context) {
    final version = _version;
    return Scaffold(
      appBar: AppBar(title: const Text('更新 Root 内核')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_stage, style: Theme.of(context).textTheme.titleMedium),
                  if (_updating) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress),
                  ],
                  const SizedBox(height: 14),
                  Text('当前版本：${version?.currentVersion ?? '未知'}'),
                  Text('最新版本：${version?.latestVersion ?? '未知'}'),
                  Text('ABI：${version?.abi ?? '未知'}'),
                  Text('文件大小：${_size(version?.size ?? -1)}'),
                  Text(
                    '发布时间：${version?.publishedAt.isEmpty ?? true ? '未知' : version!.publishedAt}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _checking || _updating ? null : _check,
            icon: const Icon(Icons.manage_search_rounded),
            label: Text(_checking ? '检查中…' : '检查版本'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _updating || version?.hasUpdate != true ? null : _update,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: Text(_updating ? '更新中…' : '更新内核'),
          ),
          if (_updating)
            TextButton(
              onPressed: _service.cancelRootCoreUpdate,
              child: const Text('取消下载'),
            ),
        ],
      ),
    );
  }
}
