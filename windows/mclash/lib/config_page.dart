import 'config_management.dart' show configActionOrder;
import 'config_management_page.dart';
import 'subscription_links.dart';
import 'subscription_usage.dart';
import 'package:flutter/material.dart';
import 'proxy_chain.dart';
import 'proxy_chain_dialog.dart';
import 'node_link.dart';
import 'add_node_dialog.dart';
import 'subscription_host.dart';
import 'subscription_host_dialog.dart';

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
                    onReorderStart: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) => setDialogState(() {
                      if (newIndex > oldIndex) newIndex--;
                      urlControllers.insert(
                          newIndex, urlControllers.removeAt(oldIndex));
                      airportNameControllers.insert(
                          newIndex, airportNameControllers.removeAt(oldIndex));
                    }),
                    children: [
                      for (var i = 0; i < urlControllers.length; i++)
                        Padding(
                          key: ObjectKey(urlControllers[i]),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
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
                                      controller: airportNameControllers[i],
                                      decoration: InputDecoration(
                                          labelText: '机场 ${i + 1} 名称',
                                          hintText: '例如：我的机场'),
                                      textInputAction: TextInputAction.next,
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: urlControllers[i],
                                      decoration: InputDecoration(
                                          labelText: '机场 ${i + 1} 订阅链接',
                                          hintText: 'https://...'),
                                      keyboardType: TextInputType.url,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      smartDashesType: SmartDashesType.disabled,
                                      smartQuotesType: SmartQuotesType.disabled,
                                    ),
                                  ],
                                ),
                              ),
                              if (urlControllers.length > 1)
                                IconButton(
                                  tooltip: '删除机场 ${i + 1}',
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => setDialogState(() {
                                    removedControllers
                                        .add(urlControllers.removeAt(i));
                                    removedControllers.add(
                                        airportNameControllers.removeAt(i));
                                  }),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setDialogState(() {
                      urlControllers.add(TextEditingController());
                      airportNameControllers.add(TextEditingController());
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('添加订阅链接'),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('拖动调整机场顺序；多个机场的节点按序号加前缀，如 1-香港'),
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
                for (var i = 0; i < urlControllers.length; i++) {
                  if (airportNameControllers[i].text.trim().isEmpty) {
                    setDialogState(
                        () => validationMessage = '请输入机场 ${i + 1} 的名称');
                    return;
                  }
                  if (urlControllers[i].text.trim().isEmpty) {
                    setDialogState(
                        () => validationMessage = '请输入机场 ${i + 1} 的订阅链接');
                    return;
                  }
                }
                try {
                  final links = subscriptionLinks(enteredUrls());
                  if (links.length != urlControllers.length) {
                    setDialogState(() => validationMessage = '订阅链接重复，请删除重复项');
                    return;
                  }
                } on FormatException catch (error) {
                  setDialogState(() => validationMessage = error.message);
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(existing == null ? '添加并下载' : '保存并更新'),
            ),
          ],
        ),
      ),
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
    if (widget.proxyRunning) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ConfigEditorPage(profile: profile)),
      );
      return;
    }

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

  Future<void> _renameProfile(ConfigProfile profile) async {
    if (!_ensureStopped()) return;

    final controller = TextEditingController(text: profile.name);
    String? validationMessage;

    final route = DialogRoute<bool>(
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
    );
    final shouldSave =
        await Navigator.of(context, rootNavigator: true).push(route) ?? false;
    await route.completed;

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

  Future<void> _manageConfiguration(
      ConfigProfile profile, ConfigManagementMode mode) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final content = await _service.getConfigContent(profile.id);
      if (!mounted) return;
      setState(() => _working = false);
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => ConfigManagementPage(
                content: content,
                mode: mode,
                onSave: (value) async {
                  await _service.saveConfigContent(
                      id: profile.id, content: value);
                },
              )));
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
        initialHost: readSubscriptionHost(content),
        onSave: (value) async {
          final latest = await _service.getConfigContent(profile.id);
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
      final saved = await showAddNodeDialog(
        context: context,
        nodes: savedManualNodeNames(content),
        onDelete: (name) async {
          final latest = await _service.getConfigContent(profile.id);
          final updated = deleteManualNode(latest, name);
          await _service.saveConfigContent(id: profile.id, content: updated);
          return savedManualNodeNames(updated);
        },
        onSave: (link) async {
          final content = await _service.getConfigContent(profile.id);
          await _service.saveConfigContent(
            id: profile.id,
            content: addNodeLink(content, link),
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

  Future<void> _editProxyChain(ConfigProfile profile, bool prepend) async {
    if (!_ensureStopped()) return;
    try {
      setState(() => _working = true);
      final content = await _service.getConfigContent(profile.id);
      final nodes = savedProxyNodeNames(content);
      if (nodes.length < 2) throw const FormatException('请先保存至少两个节点');
      if (!mounted) return;
      setState(() => _working = false);
      final sets = readProxyChainSets(content);
      final role = prepend ? 'front' : 'back';
      final existing = sets.entries
          .where((entry) => (entry.value[role] ?? []).isNotEmpty)
          .toList();
      String? id;
      if (existing.isNotEmpty) {
        id = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
              child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in existing)
                ListTile(
                  title: Text('节点链路 ${entry.key}'),
                  subtitle: Text(
                      '${entry.value[role]!.join(' → ')}\n作用节点：${(entry.value['${role}Targets'] ?? []).join('、')}'),
                  isThreeLine: true,
                  onTap: () => Navigator.of(sheetContext).pop(entry.key),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(prepend ? '新增前置链路' : '新增后置链路'),
                onTap: () => Navigator.of(sheetContext).pop('new'),
              ),
            ],
          )),
        );
        if (id == null || !mounted) return;
      }
      final chainId =
          id == null || id == 'new' ? nextProxyChainSetId(content) : id;
      final initial = sets[chainId] ?? const <String, List<String>>{};
      final saved = await showProxyChainDialog(
        context: context,
        nodes: nodes,
        prepend: prepend,
        chainLabel: '节点链路 $chainId',
        initialNodes: initial[role] ?? const [],
        initialTargets: initial['${role}Targets'] ?? const [],
        excludedTargets: [
          for (final entry in sets.entries)
            if (entry.key != chainId) ...[
              ...entry.value['front'] ?? <String>[],
              ...entry.value['back'] ?? <String>[]
            ]
        ],
        onSave: (current, other) async {
          final latest = await _service.getConfigContent(profile.id);
          await _service.saveConfigContent(
            id: profile.id,
            content: setProxyChainSet(latest, chainId, other,
                prepend: prepend, targets: current),
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
            builder: (dialogContext) => AlertDialog(
                  title: const Text('删除机场'),
                  content: Text(
                      '确定删除“$name”吗？${links.length == 1 ? '\n这是最后一个机场，会同时删除该配置。' : ''}'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('删除')),
                  ],
                )) ??
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
        builder: (dialogContext) => StatefulBuilder(
              builder: (dialogContext, setDialogState) => AlertDialog(
                title: Text(link == null
                    ? '添加机场'
                    : '${index + 1} · ${nameController.text}'),
                content: SizedBox(
                    width: double.maxFinite,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: nameController,
                          enabled: !widget.proxyRunning,
                          decoration: const InputDecoration(labelText: '机场名称')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: urlController,
                          enabled: !widget.proxyRunning,
                          decoration: InputDecoration(
                              labelText: '订阅链接',
                              hintText: 'https://...',
                              errorText: error),
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled),
                    ])),
                actions: [
                  TextButton(
                      onPressed: widget.proxyRunning
                          ? null
                          : () => Navigator.of(dialogContext)
                              .pop(link == null ? null : 'delete'),
                      child: Text(link == null ? '取消' : '删除')),
                  FilledButton(
                      onPressed: widget.proxyRunning
                          ? null
                          : () {
                              try {
                                if (nameController.text.trim().isEmpty) {
                                  throw const FormatException('请输入机场名称');
                                }
                                final entered =
                                    subscriptionLinks(urlController.text);
                                if (entered.length != 1) {
                                  throw const FormatException('每个机场只能有一个订阅链接');
                                }
                                if (links.any((other) =>
                                    other != link && other == entered.single)) {
                                  throw const FormatException('订阅链接重复');
                                }
                                Navigator.of(dialogContext).pop('save');
                              } on FormatException catch (failure) {
                                setDialogState(() => error = failure.message);
                              }
                            },
                      child: Text(link == null ? '添加' : '更新')),
                ],
              ),
            ));
    final action = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    final name = nameController.text.trim();
    final url = urlController.text.trim();
    nameController.dispose();
    urlController.dispose();
    if (!mounted) return;
    if (action == 'delete') {
      await _removeAirport(profile, link!);
    } else if (action == 'save') {
      await _applyAirportChange(
          () => _service.editSubscriptionAirport(profile.id,
              oldUrl: link, name: name, url: url),
          message: link == null ? '机场已添加' : '“$name”已更新');
    }
  }

  Future<void> _showSubscriptionActions(ConfigProfile profile) async {
    var current = profile;
    while (mounted) {
      final links = subscriptionLinks(current.url ?? '');
      List<String>? reordered;
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
            child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: double.maxFinite,
              height: links.length * 88.0,
              child: ReorderableListView(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                // ignore: deprecated_member_use
                onReorder: (oldIndex, newIndex) {
                  if (widget.proxyRunning) return;
                  if (newIndex > oldIndex) newIndex--;
                  if (newIndex == oldIndex) return;
                  reordered = [...links];
                  reordered!.insert(newIndex, reordered!.removeAt(oldIndex));
                  Navigator.of(sheetContext).pop('reorder');
                },
                children: [
                  for (var i = 0; i < links.length; i++)
                    ListTile(
                        key: ValueKey(links[i]),
                        isThreeLine: true,
                        leading: ReorderableDragStartListener(
                            index: i,
                            enabled: !widget.proxyRunning,
                            child: const Icon(Icons.drag_handle)),
                        title: Text(
                            '${i + 1} · ${current.subscriptionNameFor(links[i], i)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(subscriptionUsageSummary(
                            current.subscriptionInfoFor(links[i]))),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(sheetContext).pop(links[i])),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
                leading: const Icon(Icons.add),
                title: const Text('添加机场'),
                enabled: !widget.proxyRunning,
                onTap: () => Navigator.of(sheetContext).pop('add')),
          ])),
        )),
      );
      if (choice == null || !mounted) return;
      if (choice == 'reorder') {
        await _applyAirportChange(() =>
            _service.editSubscriptionAirport(current.id, order: reordered));
      } else {
        await _showAirportDialog(current,
            link: choice == 'add' ? null : choice);
      }
      if (!mounted) return;
      final updated = _profiles.where((entry) => entry.id == current.id);
      if (updated.isEmpty) return;
      current = updated.first;
    }
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
      'prependProxy': ('添加前置代理', Icons.first_page),
      'appendProxy': ('添加后置代理', Icons.last_page),
      'groups': ('代理组管理', Icons.account_tree_outlined),
      'filters': ('正则设置', Icons.filter_alt_outlined),
      'rules': ('规则管理', Icons.rule),
    };
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
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
                    ListTile(
                      leading: Icon(editingActions[action]!.$2),
                      title: Text(editingActions[action]!.$1),
                      enabled: !widget.proxyRunning,
                      onTap: () => Navigator.of(sheetContext).pop(action),
                    ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('修改配置名称'),
                  enabled: !widget.proxyRunning,
                  onTap: () => Navigator.of(sheetContext).pop('rename'),
                ),
                if (profile.isSubscription)
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('订阅管理'),
                    onTap: () => Navigator.of(sheetContext).pop('subscription'),
                  ),
                if (!profile.isSubscription)
                  ListTile(
                    leading: const Icon(Icons.code_outlined),
                    title: const Text('修改配置文件'),
                    enabled: !widget.proxyRunning,
                    onTap: () => Navigator.of(sheetContext).pop('editContent'),
                  ),
                ListTile(
                  leading: const Icon(Icons.visibility_outlined),
                  title: const Text('查看当前运行配置'),
                  onTap: () => Navigator.of(sheetContext).pop('runtime'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除'),
                  enabled: !widget.proxyRunning,
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'subscription':
        await _showSubscriptionActions(profile);
        await _returnToActions(profile);
        return;
      case 'rules':
      case 'groups':
      case 'filters':
        await _manageConfiguration(
            profile,
            action == 'rules'
                ? ConfigManagementMode.rules
                : action == 'groups'
                    ? ConfigManagementMode.groups
                    : ConfigManagementMode.filters);
        await _returnToActions(profile);
        return;

      case 'prependProxy':
        await _editProxyChain(profile, true);
        await _returnToActions(profile);
        return;
      case 'appendProxy':
        await _editProxyChain(profile, false);
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
            builder: (_) =>
                ConfigEditorPage(profile: profile, runtimeView: true),
          ),
        );
        return;
      case 'editContent':
        if (profile.isSubscription) return;
        if (!_ensureStopped()) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => ConfigEditorPage(profile: profile)),
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
                      Text('导入 mihomo YAML'),
                    ],
                  ),
                ),
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
                                    '点击右上角“＋”导入 mihomo YAML\n或添加机场订阅',
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
                                        _showActions(profile);
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
                                                    padding: const EdgeInsets
                                                        .symmetric(
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
