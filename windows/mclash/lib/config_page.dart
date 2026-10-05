import 'app_appearance.dart';
import 'proxy_edit_access.dart';
import 'management_style.dart';
import 'add_action_button.dart';
import 'config_management.dart' show configActionOrder;
import 'config_management_page.dart';
import 'subscription_links.dart';
import 'subscription_management_page.dart';
import 'package:flutter/material.dart';
import 'proxy_chain.dart';
import 'proxy_chain_page.dart';
import 'node_link.dart';
import 'add_node_page.dart';
import 'subscription_host.dart';
import 'subscription_host_dialog.dart';

import 'app_notice.dart';
import 'models.dart';
import 'native_proxy_service.dart';
import 'proxy_platform_service.dart';
import 'config_editor_page.dart';

enum _AddConfigAction { local, subscription }

class ConfigPage extends StatefulWidget {
  const ConfigPage(
      {super.key, required this.proxyRunning, this.service, this.proxyStatus});

  final ProxyPlatformService? service;

  final bool proxyRunning;
  final ValueNotifier<ProxyStatus>? proxyStatus;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  late final ProxyPlatformService _service =
      widget.service ?? NativeProxyService.instance;

  List<ConfigProfile> _profiles = const [];
  bool _loading = true;
  bool _working = false;
  bool _profilesExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await _service.getConfigs();
      if (!mounted) return;
      setState(() {
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

  bool get _locked => widget.proxyStatus != null
      ? widget.proxyStatus!.value != ProxyStatus.stopped
      : widget.proxyRunning;

  Widget _watchAccess(Widget Function(BuildContext) builder) =>
      ProxyEditAccess.wrap(widget.proxyStatus, builder);

  bool _ensureStopped() {
    if (!_locked) return true;
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
    final urlControllers = (existing?.url ?? '')
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map((line) => TextEditingController(text: line.trim()))
        .toList();
    if (urlControllers.isEmpty) urlControllers.add(TextEditingController());
    final airportNameControllers = [
      for (var i = 0; i < urlControllers.length; i++)
        TextEditingController(
            text:
                existing?.subscriptionNameFor(urlControllers[i].text, i) ?? ''),
    ];
    final removedControllers = <TextEditingController>[];
    String enteredUrls() =>
        urlControllers.map((controller) => controller.text).join('\n');
    String? validationMessage;

    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _watchAccess((dialogContext) =>
          StatefulBuilder(
            builder: (dialogContext, setDialogState) =>
                _watchAccess((dialogContext) => AlertDialog(
                      title: Text(existing == null ? '添加机场订阅' : '修改机场订阅'),
                      content: SizedBox(
                        width: 480,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                enabled: !_locked,
                                controller: nameController,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: '配置名称',
                                  hintText: '例如：我的代理配置',
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.maxFinite,
                                height: urlControllers.length * 148.0,
                                child: ReorderableListView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  onReorderStart: (_) => FocusManager
                                      .instance.primaryFocus
                                      ?.unfocus(),
                                  // ignore: deprecated_member_use
                                  onReorder: (oldIndex, newIndex) => _locked
                                      ? null
                                      : setDialogState(() {
                                          if (newIndex > oldIndex) newIndex--;
                                          urlControllers.insert(
                                              newIndex,
                                              urlControllers
                                                  .removeAt(oldIndex));
                                          airportNameControllers.insert(
                                              newIndex,
                                              airportNameControllers
                                                  .removeAt(oldIndex));
                                        }),
                                  children: [
                                    for (var i = 0;
                                        i < urlControllers.length;
                                        i++)
                                      Padding(
                                        key: ObjectKey(urlControllers[i]),
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          children: [
                                            ReorderableDragStartListener(
                                              enabled: !_locked,
                                              index: i,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 12),
                                                child: Column(children: [
                                                  Text('${i + 1}'),
                                                  const Icon(Icons.drag_handle)
                                                ]),
                                              ),
                                            ),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  TextField(
                                                    enabled: !_locked,
                                                    controller:
                                                        airportNameControllers[
                                                            i],
                                                    decoration: InputDecoration(
                                                        labelText:
                                                            '机场 ${i + 1} 名称',
                                                        hintText: '例如：我的机场'),
                                                    textInputAction:
                                                        TextInputAction.next,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  TextField(
                                                    enabled: !_locked,
                                                    controller:
                                                        urlControllers[i],
                                                    decoration: InputDecoration(
                                                        labelText:
                                                            '机场 ${i + 1} 订阅链接',
                                                        hintText:
                                                            'https://...'),
                                                    keyboardType:
                                                        TextInputType.url,
                                                    autocorrect: false,
                                                    enableSuggestions: false,
                                                    smartDashesType:
                                                        SmartDashesType
                                                            .disabled,
                                                    smartQuotesType:
                                                        SmartQuotesType
                                                            .disabled,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (urlControllers.length > 1)
                                              IconButton(
                                                tooltip: '删除机场 ${i + 1}',
                                                icon: const Icon(Icons
                                                    .remove_circle_outline),
                                                onPressed: _locked
                                                    ? null
                                                    : () => setDialogState(() {
                                                          removedControllers
                                                              .add(
                                                                  urlControllers
                                                                      .removeAt(
                                                                          i));
                                                          removedControllers.add(
                                                              airportNameControllers
                                                                  .removeAt(i));
                                                        }),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: AddActionButton(
                                  tooltip: '添加订阅链接',
                                  onPressed: _locked
                                      ? null
                                      : () => setDialogState(() {
                                            urlControllers
                                                .add(TextEditingController());
                                            airportNameControllers
                                                .add(TextEditingController());
                                          }),
                                ),
                              ),
                              if (validationMessage != null) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    validationMessage!,
                                    style: TextStyle(
                                      color: Theme.of(dialogContext)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: _locked
                              ? null
                              : () {
                                  if (nameController.text.isEmpty) {
                                    setDialogState(
                                        () => validationMessage = '请输入名称');
                                    return;
                                  }
                                  for (var i = 0;
                                      i < urlControllers.length;
                                      i++) {
                                    if (airportNameControllers[i]
                                        .text
                                        .trim()
                                        .isEmpty) {
                                      setDialogState(() => validationMessage =
                                          '请输入机场 ${i + 1} 的名称');
                                      return;
                                    }
                                    if (urlControllers[i].text.trim().isEmpty) {
                                      setDialogState(() => validationMessage =
                                          '请输入机场 ${i + 1} 的订阅链接');
                                      return;
                                    }
                                  }
                                  try {
                                    final links =
                                        subscriptionLinks(enteredUrls());
                                    if (links.length != urlControllers.length) {
                                      setDialogState(() =>
                                          validationMessage = '订阅链接重复，请删除重复项');
                                      return;
                                    }
                                  } on FormatException catch (error) {
                                    setDialogState(() =>
                                        validationMessage = error.message);
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop(true);
                                },
                          child: Text(existing == null ? '添加并下载' : '保存并更新'),
                        ),
                      ],
                    )),
          )),
    );
    final save =
        await Navigator.of(context, rootNavigator: true).push(route) ?? false;
    await route.completed;

    final name = nameController.text;
    final url =
        save ? normalizeSubscriptionLinks(enteredUrls()) : enteredUrls();
    final subscriptionNames = {
      for (var i = 0; i < urlControllers.length; i++)
        urlControllers[i].text.trim(): airportNameControllers[i].text.trim(),
    };
    nameController.dispose();
    for (final controller in [
      ...urlControllers,
      ...airportNameControllers,
      ...removedControllers
    ]) {
      controller.dispose();
    }
    if (!save) return;

    try {
      setState(() => _working = true);
      if (!_ensureStopped()) return;
      final profiles = existing == null
          ? await _service.addSubscription(
              name: name, url: url, subscriptionNames: subscriptionNames)
          : await _service.updateSubscription(
              id: existing.id,
              name: name,
              url: url,
              subscriptionNames: subscriptionNames,
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
      if (mounted) setState(() => _profilesExpanded = false);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete(ConfigProfile profile) async {
    if (!_ensureStopped()) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) =>
              _watchAccess((dialogContext) => AlertDialog(
                    title: const Text('删除配置'),
                    content: Text('确定删除“${profile.name}”吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('取消'),
                      ),
                      DestructiveActionButton(
                        onPressed: _locked
                            ? null
                            : () => Navigator.of(dialogContext).pop(true),
                        child: const Text('删除'),
                      ),
                    ],
                  )),
        ) ??
        false;
    if (!confirmed) return;

    try {
      setState(() => _working = true);
      if (!_ensureStopped()) return;
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
    if (_locked) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
            builder: (_) => _watchAccess((_) => ConfigEditorPage(
                profile: profile,
                service: _service,
                proxyStatus: widget.proxyStatus))),
      );
      return;
    }

    final colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _watchAccess((sheetContext) => SafeArea(
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
                      style: TextStyle(
                          color: colors.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    _locked
                        ? '代理运行中：当前页面仅供查看，停止代理后可切换或管理配置。'
                        : '点击非当前配置可切换，长按可管理。',
                    style:
                        TextStyle(color: colors.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          )),
    );
  }

  Future<void> _renameProfile(ConfigProfile profile) async {
    if (!_ensureStopped()) return;

    final controller = TextEditingController(text: profile.name);
    String? validationMessage;

    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => _watchAccess((dialogContext) =>
          StatefulBuilder(
            builder: (dialogContext, setDialogState) =>
                _watchAccess((dialogContext) => AlertDialog(
                      title: const Text('配置名称'),
                      content: TextField(
                        enabled: !_locked,
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: '名称',
                          errorText: validationMessage,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (_locked) return;
                          if (controller.text.trim().isEmpty) {
                            setDialogState(() => validationMessage = '请输入配置名称');
                            return;
                          }
                          Navigator.of(dialogContext).pop(true);
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: _locked
                              ? null
                              : () {
                                  if (controller.text.trim().isEmpty) {
                                    setDialogState(
                                        () => validationMessage = '请输入配置名称');
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop(true);
                                },
                          child: const Text('保存'),
                        ),
                      ],
                    )),
          )),
    );
    final shouldSave =
        await Navigator.of(context, rootNavigator: true).push(route) ?? false;
    await route.completed;

    final name = controller.text.trim();
    controller.dispose();
    if (!shouldSave) return;

    try {
      setState(() => _working = true);
      if (!_ensureStopped()) return;
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

  Future<void> _manageConfiguration(
      ConfigProfile profile, ConfigManagementMode mode) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final content = await _service.getConfigContent(profile.id);
      if (!mounted) return;
      setState(() => _working = false);
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => _watchAccess((_) => ConfigManagementPage(
                content: content,
                mode: mode,
                onSave: (value) async {
                  if (!_ensureStopped()) throw StateError('请先停止代理再修改配置');
                  await _service.saveConfigContent(
                      id: profile.id, content: value);
                },
              ))));
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editSubscriptionHost(ConfigProfile profile) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final content = await _service.getConfigContent(profile.id);
      if (!mounted) return;
      setState(() => _working = false);
      final saved = await showSubscriptionHostDialog(
        context: context,
        proxyStatus: widget.proxyStatus,
        initialHost: readSubscriptionHost(content),
        onSave: (value) async {
          final latest = await _service.getConfigContent(profile.id);
          if (!_ensureStopped()) throw StateError('请先停止代理再修改配置');
          await _service.saveConfigContent(
            id: profile.id,
            content: editSubscriptionHost(latest, value),
          );
        },
      );
      if (saved && mounted) await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addNode(ConfigProfile profile) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final content = await _service.getConfigContent(profile.id);
      if (!mounted) return;
      setState(() => _working = false);
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => _watchAccess((_) => AddNodePage(
              nodes: savedManualNodeNames(content),
              onReorder: (order) async {
                final latest = await _service.getConfigContent(profile.id);
                final updated = reorderManualNodes(latest, order);
                if (!_ensureStopped()) throw StateError('请先停止代理再修改配置');
                await _service.saveConfigContent(
                    id: profile.id, content: updated);
                return savedManualNodeNames(updated);
              },
              onDelete: (name) async {
                final latest = await _service.getConfigContent(profile.id);
                final updated = deleteManualNode(latest, name);
                if (!_ensureStopped()) throw StateError('请先停止代理再修改配置');
                await _service.saveConfigContent(
                    id: profile.id, content: updated);
                return savedManualNodeNames(updated);
              },
              onSave: (link) async {
                final content = await _service.getConfigContent(profile.id);
                final updated = addNodeLink(content, link);
                if (!_ensureStopped()) throw StateError('请先停止代理再修改配置');
                await _service.saveConfigContent(
                    id: profile.id, content: updated);
                return savedManualNodeNames(updated);
              },
            )),
      ));
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editProxyChain(ConfigProfile profile) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final content = await _service.getConfigContent(profile.id);
      if (savedProxyNodeNames(content).length < 2) {
        throw const FormatException('请先保存至少两个节点');
      }
      if (!mounted) return;
      setState(() => _working = false);
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _watchAccess((_) => ProxyChainPage(
                content: content,
                onSave: (next) async {
                  if (!_ensureStopped()) throw StateError('请先停止代理再修改配置');
                  await _service.saveConfigContent(
                      id: profile.id, content: next);
                },
              ))));
      if (mounted) await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _returnToActions(ConfigProfile profile) async {
    if (!mounted) return;
    for (final current in _profiles) {
      if (current.id == profile.id) {
        await _showActions(current);
        return;
      }
    }
  }

  Future<void> _applyAirportChange(
      Future<List<ConfigProfile>> Function() operation,
      {String? message}) async {
    if (!_ensureStopped()) return;
    setState(() => _working = true);
    try {
      final profiles = await operation();
      if (!mounted) return;
      setState(() => _profiles = profiles);
      if (message != null) AppNotice.show(context, message);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _removeAirport(ConfigProfile profile, String link) async {
    if (!_ensureStopped()) return;
    final links = subscriptionLinks(profile.url ?? '');
    final name = profile.subscriptionNameFor(link, links.indexOf(link));
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) =>
                _watchAccess((dialogContext) => AlertDialog(
                      title: const Text('删除机场'),
                      content: Text(
                          '确定删除“$name”吗？${links.length == 1 ? '\n这是最后一个机场，会同时删除该配置。' : ''}'),
                      actions: [
                        TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('取消')),
                        DestructiveActionButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('删除')),
                      ],
                    ))) ??
        false;
    if (!confirmed || !mounted) return;
    await _applyAirportChange(() => links.length == 1
        ? _service.deleteConfig(profile.id)
        : _service.editSubscriptionAirport(profile.id, oldUrl: link));
  }

  Future<void> _showAirportDialog(ConfigProfile profile, {String? link}) async {
    final links = subscriptionLinks(profile.url ?? '');
    final index = link == null ? links.length : links.indexOf(link);
    final nameController = TextEditingController(
        text: link == null ? '' : profile.subscriptionNameFor(link, index));
    final urlController = TextEditingController(text: link ?? '');
    String? error;
    final route = DialogRoute<String>(
        context: context,
        builder: (dialogContext) => _watchAccess((dialogContext) =>
            StatefulBuilder(
              builder: (dialogContext, setDialogState) =>
                  _watchAccess((dialogContext) => AlertDialog(
                        title: Text(link == null ? '添加机场' : '编辑机场'),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        content: SizedBox(
                            width: 480,
                            child: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  TextField(
                                      enabled: !_locked,
                                      controller: nameController,
                                      decoration: InputDecoration(
                                        labelText: '机场名称',
                                        filled: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 16),
                                        fillColor: Theme.of(dialogContext)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.45),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            borderSide: BorderSide.none),
                                      )),
                                  const SizedBox(height: 12),
                                  TextField(
                                      enabled: !_locked,
                                      controller: urlController,
                                      decoration: InputDecoration(
                                          labelText: '订阅链接',
                                          filled: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 16),
                                          fillColor: Theme.of(dialogContext)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.45),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              borderSide: BorderSide.none),
                                          hintText: 'https://...',
                                          errorText: error),
                                      keyboardType: TextInputType.url,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      smartDashesType: SmartDashesType.disabled,
                                      smartQuotesType:
                                          SmartQuotesType.disabled),
                                ]))),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: _locked
                                  ? null
                                  : () {
                                      try {
                                        if (nameController.text
                                            .trim()
                                            .isEmpty) {
                                          throw const FormatException(
                                              '请输入机场名称');
                                        }
                                        final entered = subscriptionLinks(
                                            urlController.text);
                                        if (entered.length != 1) {
                                          throw const FormatException(
                                              '每个机场只能有一个订阅链接');
                                        }
                                        if (links.any((other) =>
                                            other != link &&
                                            other == entered.single)) {
                                          throw const FormatException('订阅链接重复');
                                        }
                                        Navigator.of(dialogContext).pop('save');
                                      } on FormatException catch (failure) {
                                        setDialogState(
                                            () => error = failure.message);
                                      }
                                    },
                              child: Text(link == null ? '添加' : '保存并更新')),
                        ],
                      )),
            )));
    final action = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    final name = nameController.text.trim();
    final url = urlController.text.trim();
    nameController.dispose();
    urlController.dispose();
    if (!mounted) return;
    if (action == 'save' && _ensureStopped()) {
      await _applyAirportChange(
          () => _service.editSubscriptionAirport(profile.id,
              oldUrl: link, name: name, url: url),
          message: link == null ? '机场已添加' : '“$name”已更新');
    }
  }

  Future<void> _showSubscriptionActions(ConfigProfile profile) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => _subscriptionPanel(profile),
    ));
  }

  Widget _subscriptionPanel(ConfigProfile profile, {bool embedded = false}) {
    ConfigProfile? latestProfile() {
      for (final current in _profiles) {
        if (current.id == profile.id) return current;
      }
      return null;
    }

    return _watchAccess((_) => SubscriptionManagementPage(
          key: ValueKey(profile.id),
          embedded: embedded,
          profile: profile,
          proxyRunning: _locked,
          onEdit: (current, link) async {
            await _showAirportDialog(current, link: link);
            return latestProfile();
          },
          onUpdate: (current, link) async {
            final links = subscriptionLinks(current.url ?? '');
            final name = current.subscriptionNameFor(link, links.indexOf(link));
            await _applyAirportChange(
                () => _service.editSubscriptionAirport(current.id,
                    oldUrl: link, name: name, url: link),
                message: '“$name”已更新');
            return latestProfile();
          },
          onDelete: (current, link) async {
            await _removeAirport(current, link);
            return latestProfile();
          },
          onReorder: (current, order) async {
            await _applyAirportChange(() =>
                _service.editSubscriptionAirport(current.id, order: order));
            return latestProfile();
          },
        ));
  }

  Future<void> _showActions(ConfigProfile profile) async {
    if (_working) return;
    var orderedActions = configActionOrder('');
    setState(() => _working = true);
    try {
      final content = await _service.getConfigContent(profile.id);
      orderedActions = configActionOrder(content);
    } catch (_) {
      // Keep management available when a profile file is missing or unreadable.
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    const editingActions = {
      'addNode': ('添加节点', Icons.add_link),
      'host': ('修改 Host', Icons.dns_outlined),
      'prependProxy': ('链式节点', Icons.link),
      'groups': ('代理组管理', Icons.account_tree_outlined),
      'rules': ('规则管理', Icons.rule),
    };
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _watchAccess((sheetContext) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!profile.isSubscription) ...[
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(profile.name),
                        subtitle: const Text('本地 YAML 配置'),
                      ),
                      const Divider(height: 1),
                    ],
                    for (final action in orderedActions)
                      if (action != 'host' || profile.isSubscription)
                        ManagementMenuTile(
                          icon: editingActions[action]!.$2,
                          title: editingActions[action]!.$1,
                          enabled: !_locked,
                          onTap: () => Navigator.of(sheetContext).pop(action),
                        ),
                    const Divider(height: 1),
                    ManagementMenuTile(
                      icon: Icons.drive_file_rename_outline,
                      title: '修改配置名称',
                      enabled: !_locked,
                      onTap: () => Navigator.of(sheetContext).pop('rename'),
                    ),
                    if (profile.isSubscription)
                      ManagementMenuTile(
                        icon: Icons.cloud_outlined,
                        title: '订阅管理',
                        onTap: () =>
                            Navigator.of(sheetContext).pop('subscription'),
                      ),
                    if (!profile.isSubscription)
                      ManagementMenuTile(
                        icon: Icons.code_outlined,
                        title: '修改配置文件',
                        enabled: !_locked,
                        onTap: () =>
                            Navigator.of(sheetContext).pop('editContent'),
                      ),
                    ManagementMenuTile(
                      icon: Icons.visibility_outlined,
                      title: '查看当前运行配置',
                      onTap: () => Navigator.of(sheetContext).pop('runtime'),
                    ),
                    ManagementMenuTile(
                      icon: Icons.delete_outline,
                      title: '删除',
                      destructive: true,
                      enabled: !_locked,
                      onTap: () => Navigator.of(sheetContext).pop('delete'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          )),
    );

    if (!mounted) return;
    switch (action) {
      case 'subscription':
        await _showSubscriptionActions(profile);
        await _returnToActions(profile);
        return;
      case 'rules':
      case 'groups':
        await _manageConfiguration(
            profile,
            action == 'rules'
                ? ConfigManagementMode.rules
                : ConfigManagementMode.groups);
        await _returnToActions(profile);
        return;

      case 'prependProxy':
        await _editProxyChain(profile);
        await _returnToActions(profile);
        return;
      case 'addNode':
        await _addNode(profile);
        await _returnToActions(profile);
        return;
      case 'host':
        await _editSubscriptionHost(profile);
        await _returnToActions(profile);
        return;
      case 'select':
        await _select(profile);
        return;
      case 'runtime':
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ConfigEditorPage(
                profile: profile,
                runtimeView: true,
                service: _service,
                proxyStatus: widget.proxyStatus),
          ),
        );
        return;
      case 'editContent':
        if (profile.isSubscription) return;
        if (!_ensureStopped()) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
              builder: (_) => _watchAccess((_) => ConfigEditorPage(
                  profile: profile,
                  service: _service,
                  proxyStatus: widget.proxyStatus))),
        );
        await _load();
        await _returnToActions(profile);
        return;
      case 'rename':
        await _renameProfile(profile);
        await _returnToActions(profile);
        return;
      case 'delete':
        await _delete(profile);
        await _returnToActions(profile);
        return;
    }
  }

  List<String> _airportLinks(ConfigProfile profile) {
    try {
      return subscriptionLinks(profile.url ?? '');
    } on FormatException {
      return const [];
    }
  }

  void _showError(Object error) {
    AppNotice.show(context, error.toString(), error: true);
  }

  List<ConfigProfile> get _displayProfiles => [
        ..._profiles.where((profile) => profile.active),
        ..._profiles.where((profile) => !profile.active),
      ];

  Widget _configCard(ConfigProfile profile, {bool stacked = false}) => Card(
      key: ValueKey('config-card-${profile.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _working
            ? null
            : () {
                if (stacked) {
                  setState(() => _profilesExpanded = true);
                  return;
                }
                if (_locked || profile.active) {
                  _showConfigDetails(profile);
                } else {
                  _select(profile);
                }
              },
        onLongPress: _working ? null : () => _showActions(profile),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(profile.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              if (profile.active && !stacked) ...[
                const SizedBox(width: 8),
                Text('当前使用',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFA6D7B8)
                            : const Color(0xFF367151))),
              ],
              if (stacked)
                TextButton(
                  key: const ValueKey('toggle-config-stack'),
                  onPressed: _working
                      ? null
                      : () => setState(() => _profilesExpanded = true),
                  child: const Text('展开'),
                ),
            ]),
            SizedBox(height: stacked ? 4 : 6),
            Row(children: [
              Expanded(
                child: Text(
                    profile.isSubscription
                        ? '${_airportLinks(profile).length} 个机场 · 长按管理'
                        : '本地 YAML · 长按管理',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              if (stacked && profile.active) ...[
                const SizedBox(width: 8),
                Text('当前使用',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFFA6D7B8)
                            : const Color(0xFF367151))),
              ],
            ]),
          ]),
        ),
      ));

  Widget _configCards() {
    final profiles = _displayProfiles;
    if (profiles.length == 1) return _configCard(profiles.first);
    if (_profilesExpanded) {
      return Column(children: [
        for (var i = 0; i < profiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _configCard(profiles[i]),
        ],
      ]);
    }
    final depth = (profiles.length - 1).clamp(0, 2).toInt();
    final colors = Theme.of(context).colorScheme;
    return Stack(key: const ValueKey('config-profile-stack'), children: [
      for (var layer = depth; layer > 0; layer--)
        Positioned(
          left: layer * 6.0,
          right: layer * 6.0,
          top: layer * 8.0,
          bottom: (depth - layer) * 8.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryContainer
                  .withValues(alpha: layer == 2 ? .45 : .75),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      Padding(
        padding: EdgeInsets.only(bottom: depth * 8.0),
        child: _configCard(profiles.first, stacked: true),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      padding: EdgeInsets.fromLTRB(
                          MediaQuery.sizeOf(context).width < 380 ? 12 : 16,
                          0,
                          MediaQuery.sizeOf(context).width < 380 ? 12 : 16,
                          88),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Expanded(
                                child: Text('配置与订阅',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium)),
                            Text('${_profiles.length} 个配置',
                                style: Theme.of(context).textTheme.bodySmall),
                            if (_profiles.length > 1 && _profilesExpanded)
                              TextButton(
                                key: const ValueKey('toggle-config-stack'),
                                onPressed: _working
                                    ? null
                                    : () => setState(() =>
                                        _profilesExpanded = !_profilesExpanded),
                                child: Text(_profilesExpanded ? '收起' : '展开'),
                              ),
                          ]),
                        ),
                        if (_profiles.isEmpty)
                          Card(
                              child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 24),
                            child: Column(children: [
                              Text('尚未添加配置',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text('点击右下角“＋”导入 YAML或添加机场订阅',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ]),
                          )),
                        if (_profiles.isNotEmpty) ...[
                          _configCards(),
                          const SizedBox(height: 10),
                        ],
                        for (final profile in _profiles)
                          if (profile.active &&
                              profile.isSubscription &&
                              _airportLinks(profile).isNotEmpty) ...[
                            const PulseSectionLabel('机场订阅'),
                            _subscriptionPanel(profile, embedded: true),
                          ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: PopupMenuButton<_AddConfigAction>(
        enabled: !_working && !_locked,
        tooltip: '添加配置',
        onSelected: _handleAdd,
        offset: const Offset(0, -128),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _AddConfigAction.local,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_open_outlined, size: 21),
                SizedBox(width: 11),
                Text('导入本地 YAML'),
              ],
            ),
          ),
          PopupMenuItem(
            value: _AddConfigAction.subscription,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_download_outlined, size: 21),
                SizedBox(width: 11),
                Text('添加机场订阅'),
              ],
            ),
          ),
        ],
        child: AddActionIcon(enabled: !_working && !_locked),
      ),
    );
  }
}
