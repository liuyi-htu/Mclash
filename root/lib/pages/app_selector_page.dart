import 'package:flutter/material.dart';

import '../core/models.dart';
import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class AppSelectorPage extends StatefulWidget {
  const AppSelectorPage({super.key});

  @override
  State<AppSelectorPage> createState() => _AppSelectorPageState();
}

class _AppSelectorPageState extends State<AppSelectorPage> {
  final _service = NativeProxyService.instance;
  final _searchController = TextEditingController();

  List<InstalledApp> _apps = const [];
  Set<String> _selected = <String>{};
  AppProxyMode _mode = AppProxyMode.exclude;
  bool _loading = true;
  bool _saving = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        _service.getInstalledApps(),
        _service.getSelectedPackages(),
        _service.getMode(),
      ]);
      if (!mounted) return;
      setState(() {
        _apps = results[0] as List<InstalledApp>;
        final visiblePackages = _apps.map((app) => app.packageName).toSet();
        _selected = (results[1] as Set<String>).intersection(visiblePackages);
        _mode = results[2] as AppProxyMode;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopSnackBar(context, SnackBar(content: Text('读取应用列表失败：$error')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.saveAppFilter(mode: _mode, packageNames: _selected);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopSnackBar(context, SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final matching = _apps.where((app) {
      if (_query.isEmpty) return true;
      final query = _query.toLowerCase();
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query) ||
          (app.isSystemApp && '系统应用'.contains(_query));
    }).toList(growable: false);
    final filtered = <InstalledApp>[
      ...matching.where((app) => _selected.contains(app.packageName)),
      ...matching.where((app) => !_selected.contains(app.packageName)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('分应用代理'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.tonalIcon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 19),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SegmentedButton<AppProxyMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<AppProxyMode>(
                            value: AppProxyMode.exclude,
                            icon: Icon(Icons.block_outlined),
                            label: Text('选中的不代理'),
                          ),
                          ButtonSegment<AppProxyMode>(
                            value: AppProxyMode.include,
                            icon: Icon(Icons.check_circle_outline),
                            label: Text('仅代理选中的'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (selection) {
                          setState(() => _mode = selection.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.comfortable,
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索应用名称、包名或“系统应用”',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: (value) {
                      setState(() => _query = value.trim());
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Row(
                    children: [
                      Text(
                        '应用列表',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        '已选 ${_selected.length} 个',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final app = filtered[index];
                      final selected = _selected.contains(app.packageName);
                      return Card(
                        child: CheckboxListTile(
                          value: selected,
                          controlAffinity: ListTileControlAffinity.trailing,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          title: Text(
                            app.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            app.isSystemApp
                                ? '系统应用 · ${app.packageName}'
                                : app.packageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: selected
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.android_rounded,
                              color: selected
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                          onChanged: (checked) {
                            setState(() {
                              if (checked ?? false) {
                                _selected.add(app.packageName);
                              } else {
                                _selected.remove(app.packageName);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
