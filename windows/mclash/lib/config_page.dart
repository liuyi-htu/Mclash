import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'models.dart';
import 'native_proxy_service.dart';
import 'config_editor_page.dart';

enum _AddConfigAction { local, subscription }

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key, required this.proxyRunning});

  final bool proxyRunning;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final _service = NativeProxyService.instance;

  List<ConfigProfile> _profiles = const [];
  bool _loading = true;
  bool _working = false;
  bool _testingSubscriptionUrl = false;
  CoreType _coreType = CoreType.mihomo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final coreType = await _service.getCoreType();
      final profiles = await _service.getConfigs();
      if (!mounted) return;
      setState(() {
        _coreType = coreType;
        _profiles = profiles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _handleAdd(_AddConfigAction action) async {
    if (!_ensureStopped()) return;

    switch (action) {
      case _AddConfigAction.local:
        await _importLocal();
        return;
      case _AddConfigAction.subscription:
        await _showSubscriptionEditor();
        return;
    }
  }

  bool _ensureStopped() {
    if (!widget.proxyRunning) return true;
    _showError('请先停止代理再修改配置');
    return false;
  }

  Future<void> _importLocal() async {
    try {
      setState(() => _working = true);
      String? previousActiveId;
      for (final profile in _profiles) {
        if (profile.active) previousActiveId = profile.id;
      }
      final profiles = await _service.importConfigs();
      if (!mounted) return;
      setState(() => _profiles = profiles);
      String? activeId;
      for (final profile in profiles) {
        if (profile.active) activeId = profile.id;
      }
      if (activeId != null && activeId != previousActiveId) {
        AppNotice.show(context, '配置已导入并自动选中');
      }
    } catch (error) {
      if (!mounted) return;
      if (!error.toString().contains('未选择配置文件')) {
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showSubscriptionEditor({ConfigProfile? existing}) async {
    if (!_ensureStopped()) return;

    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(text: existing?.url ?? '');
    String? validationMessage;

    final save =
        await showDialog<bool>(
          context: context,
          barrierDismissible: !_working,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text(existing == null ? '添加机场订阅' : '修改机场订阅'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '例如：我的机场',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: '订阅链接',
                        hintText: 'https://...',
                        helperText: '使用 Mclash/mihomo 订阅链接',
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                    ),
                    if (validationMessage != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isEmpty) {
                      setDialogState(() => validationMessage = '请输入名称');
                      return;
                    }
                    if (urlController.text.isEmpty) {
                      setDialogState(() => validationMessage = '请输入订阅链接');
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(existing == null ? '添加并下载' : '保存并更新'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    final name = nameController.text;
    final url = urlController.text;
    nameController.dispose();
    urlController.dispose();
    if (!save) return;

    try {
      setState(() => _working = true);
      final profiles = existing == null
          ? await _service.addSubscription(name: name, url: url)
          : await _service.updateSubscription(
              id: existing.id,
              name: name,
              url: url,
            );
      if (!mounted) return;
      setState(() => _profiles = profiles);
      AppNotice.show(context, existing == null ? '订阅已添加' : '订阅已修改并更新');
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _select(ConfigProfile profile) async {
    if (profile.active || !_ensureStopped()) return;
    try {
      setState(() => _working = true);
      await _service.selectConfig(profile.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refreshSubscription(ConfigProfile profile) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final profiles = await _service.refreshSubscription(profile.id);
      if (!mounted) return;
      setState(() => _profiles = profiles);
      AppNotice.show(context, '“${profile.name}”已更新');
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(ConfigProfile profile) async {
    if (!_ensureStopped()) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除配置'),
            content: Text('确定删除“${profile.name}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      setState(() => _working = true);
      final profiles = await _service.deleteConfig(profile.id);
      if (!mounted) return;
      setState(() => _profiles = profiles);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showConfigDetails(ConfigProfile profile) async {
    final colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: profile.active
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      profile.isSubscription
                          ? Icons.cloud_outlined
                          : Icons.description_outlined,
                      color: profile.active
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profile.isSubscription ? '机场订阅' : '本地 YAML 配置',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (profile.active)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '当前使用',
                        style: TextStyle(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              if (profile.isSubscription && profile.url != null) ...[
                const SizedBox(height: 18),
                const Text(
                  '订阅链接',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  profile.url!,
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                widget.proxyRunning
                    ? '代理运行中：当前页面仅供查看，停止代理后可切换或管理配置。'
                    : '点击非当前配置可切换，长按可管理。',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameLocalProfile(ConfigProfile profile) async {
    if (!_ensureStopped()) return;

    final controller = TextEditingController(text: profile.name);
    String? validationMessage;

    final shouldSave =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: const Text('配置名称'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '名称',
                  errorText: validationMessage,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (controller.text.trim().isEmpty) {
                    setDialogState(() => validationMessage = '请输入配置名称');
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (controller.text.trim().isEmpty) {
                      setDialogState(() => validationMessage = '请输入配置名称');
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    final name = controller.text.trim();
    controller.dispose();
    if (!shouldSave) return;

    try {
      setState(() => _working = true);
      final profiles = await _service.renameConfig(id: profile.id, name: name);
      if (!mounted) return;
      setState(() => _profiles = profiles);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showActions(ConfigProfile profile) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                profile.isSubscription
                    ? Icons.cloud_outlined
                    : Icons.description_outlined,
              ),
              title: Text(profile.name),
              subtitle: Text(
                profile.isSubscription
                    ? (profile.url ?? '订阅链接不可用')
                    : '本地 YAML 配置',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            if (!profile.active)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('设为当前配置'),
                onTap: () => Navigator.of(sheetContext).pop('select'),
              ),
            if (profile.isSubscription)
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('检测订阅链接'),
                onTap: () => Navigator.of(sheetContext).pop('testUrl'),
              ),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: const Text('修改配置内容'),
              onTap: () => Navigator.of(sheetContext).pop('editContent'),
            ),
            if (profile.isSubscription)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('更新订阅'),
                onTap: () => Navigator.of(sheetContext).pop('refresh'),
              ),
            if (profile.isSubscription)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('修改订阅'),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
            if (!profile.isSubscription)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('修改配置名称'),
                onTap: () => Navigator.of(sheetContext).pop('rename'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'select':
        await _select(profile);
        return;
      case 'refresh':
        await _refreshSubscription(profile);
        return;
      case 'testUrl':
        await _testSubscriptionUrl(profile);
        return;
      case 'editContent':
        if (!_ensureStopped()) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => ConfigEditorPage(profile: profile)),
        );
        await _load();
        return;
      case 'edit':
        await _showSubscriptionEditor(existing: profile);
        return;
      case 'rename':
        await _renameLocalProfile(profile);
        return;
      case 'delete':
        await _delete(profile);
        return;
    }
  }

  Future<void> _testSubscriptionUrl(ConfigProfile profile) async {
    if (_testingSubscriptionUrl) return;
    setState(() => _testingSubscriptionUrl = true);
    try {
      final test = await _service.testSubscriptionUrl(profile.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('订阅链接检测'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '订阅服务器响应时间：${test.responseTimeMs == null ? '—' : '${test.responseTimeMs} ms'}',
              ),
              Text('HTTP 状态码：${test.statusCode ?? '—'}'),
              Text(
                '内容大小：${test.contentLength == null ? '—' : '${test.contentLength} 字节'}',
              ),
              Text('内容类型：${test.contentType ?? '—'}'),
              const SizedBox(height: 10),
              Text('检测结果：${test.message}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _testingSubscriptionUrl = false);
    }
  }

  void _showError(Object error) {
    AppNotice.show(context, error.toString(), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('配置文件'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: PopupMenuButton<_AddConfigAction>(
              enabled: !_working && !widget.proxyRunning,
              tooltip: widget.proxyRunning ? '请先停止代理' : '添加配置',
              onSelected: _handleAdd,
              constraints: const BoxConstraints(minWidth: 190, maxWidth: 230),
              icon: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _AddConfigAction.local,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.file_open_outlined),
                      const SizedBox(width: 12),
                      Text(
                        _coreType == CoreType.mihomo
                            ? '导入 mihomo YAML'
                            : '导入 sing-box JSON',
                      ),
                    ],
                  ),
                ),
                if (_coreType == CoreType.mihomo)
                  const PopupMenuItem(
                    value: _AddConfigAction.subscription,
                    height: 48,
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_download_outlined),
                        SizedBox(width: 12),
                        Text('添加机场订阅'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_working) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        if (widget.proxyRunning) ...[
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: colors.tertiaryContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: colors.onTertiaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '代理运行期间只能查看配置，停止代理后才能修改。',
                                    style: TextStyle(
                                      color: colors.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF356AE6), Color(0xFF5B8CFF)],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: const Icon(
                                  Icons.folder_copy_outlined,
                                  color: Colors.white,
                                  size: 29,
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '配置中心',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_profiles.length} 个配置 · 点击切换 · 长按管理',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.80,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (_profiles.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 38,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: colors.primaryContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.note_add_outlined,
                                      size: 34,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    '尚未添加配置',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    _coreType == CoreType.mihomo
                                        ? '点击右上角“＋”导入 mihomo YAML\n或添加机场订阅'
                                        : '点击右上角“＋”导入 sing-box JSON',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final profile in _profiles) ...[
                            Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: _working
                                    ? null
                                    : () {
                                        if (widget.proxyRunning ||
                                            profile.active) {
                                          _showConfigDetails(profile);
                                        } else {
                                          _select(profile);
                                        }
                                      },
                                onLongPress: _working
                                    ? null
                                    : () {
                                        if (widget.proxyRunning) {
                                          _showConfigDetails(profile);
                                        } else {
                                          _showActions(profile);
                                        }
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.all(15),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: profile.active
                                              ? colors.primaryContainer
                                              : colors.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Icon(
                                          profile.isSubscription
                                              ? Icons.cloud_outlined
                                              : Icons.description_outlined,
                                          color: profile.active
                                              ? colors.onPrimaryContainer
                                              : colors.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    profile.name,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 15.5,
                                                    ),
                                                  ),
                                                ),
                                                if (profile.active)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 9,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: colors
                                                          .primaryContainer,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '当前',
                                                      style: TextStyle(
                                                        color: colors
                                                            .onPrimaryContainer,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              widget.proxyRunning
                                                  ? (profile.isSubscription
                                                        ? '机场订阅 · 点击查看'
                                                        : '本地 YAML · 点击查看')
                                                  : (profile.isSubscription
                                                        ? '机场订阅 · 长按管理'
                                                        : '本地 YAML · 长按管理'),
                                              style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        profile.active
                                            ? Icons.check_circle_rounded
                                            : Icons.chevron_right_rounded,
                                        color: profile.active
                                            ? colors.primary
                                            : colors.outline,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
