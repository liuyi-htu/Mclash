import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/native_proxy_service.dart';
import '../shared/top_notice.dart';

class ProxyPanelPage extends StatefulWidget {
  const ProxyPanelPage({required this.proxyRunning, super.key});

  final bool proxyRunning;

  @override
  State<ProxyPanelPage> createState() => _ProxyPanelPageState();
}

class _ProxyPanelPageState extends State<ProxyPanelPage> {
  final _service = NativeProxyService.instance;
  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..findProxy = (_) => 'DIRECT';

  var _loading = false;
  var _testingAllNodes = false;
  List<_ProxyGroup> _groups = const [];
  final Map<String, String> _providerByNode = {};
  final Map<String, _DelayResult> _delaysByNode = {};
  final Set<String> _testingNodes = {};
  Future<void> _delayTestQueue = Future<void>.value();
  Future<void> _saveQueue = Future<void>.value();

  static const _delayTimeoutMs = 3000;
  static const _proxyDelayTestUrl = 'https://www.gstatic.com/generate_204';
  static const _directDelayTestUrl = 'http://connect.rom.miui.com/generate_204';
  static const _internationalDelayTestUrl = 'http://cloudflare.com';
  static final _cnNodePattern = RegExp(
    r'(CN|北京|上海|天津|重庆|河北|石家庄|唐山|秦皇岛|邯郸|邢台|保定|张家口|承德|沧州|廊坊|衡水|'
    r'山西|太原|大同|阳泉|长治|晋城|朔州|晋中|运城|忻州|临汾|吕梁|内蒙古|呼和浩特|包头|乌海|赤峰|通辽|鄂尔多斯|呼伦贝尔|巴彦淖尔|乌兰察布|'
    r'辽宁|沈阳|大连|鞍山|抚顺|本溪|丹东|锦州|营口|阜新|辽阳|盘锦|铁岭|朝阳|葫芦岛|吉林|长春|四平|辽源|通化|白山|松原|白城|延边|延吉|'
    r'黑龙江|哈尔滨|齐齐哈尔|鸡西|鹤岗|双鸭山|大庆|伊春|佳木斯|七台河|牡丹江|黑河|绥化|江苏|南京|无锡|徐州|常州|苏州|南通|连云港|淮安|盐城|扬州|镇江|泰州|宿迁|'
    r'浙江|杭州|宁波|温州|嘉兴|湖州|绍兴|金华|衢州|舟山|台州|丽水|安徽|合肥|芜湖|蚌埠|淮南|马鞍山|淮北|铜陵|安庆|黄山|滁州|阜阳|宿州|六安|亳州|池州|宣城|'
    r'福建|福州|厦门|莆田|三明|泉州|漳州|南平|龙岩|宁德|江西|南昌|景德镇|萍乡|九江|新余|鹰潭|赣州|吉安|宜春|抚州|上饶|'
    r'山东|济南|青岛|淄博|枣庄|东营|烟台|潍坊|济宁|泰安|威海|日照|临沂|德州|聊城|滨州|菏泽|河南|郑州|开封|洛阳|平顶山|安阳|鹤壁|新乡|焦作|濮阳|许昌|漯河|三门峡|南阳|商丘|信阳|周口|驻马店|济源|'
    r'湖北|武汉|黄石|十堰|宜昌|襄阳|鄂州|荆门|孝感|荆州|黄冈|咸宁|随州|恩施|仙桃|潜江|天门|湖南|长沙|株洲|湘潭|衡阳|邵阳|岳阳|常德|张家界|益阳|郴州|永州|怀化|娄底|湘西|'
    r'广东|广州|韶关|深圳|珠海|汕头|佛山|江门|湛江|茂名|肇庆|惠州|梅州|汕尾|河源|阳江|清远|东莞|中山|潮州|揭阳|云浮|广西|南宁|柳州|桂林|梧州|北海|防城港|钦州|贵港|玉林|百色|贺州|河池|来宾|崇左|'
    r'海南|海口|三亚|三沙|儋州|五指山|琼海|文昌|万宁|东方|四川|成都|自贡|攀枝花|泸州|德阳|绵阳|广元|遂宁|内江|乐山|南充|眉山|宜宾|广安|达州|雅安|巴中|资阳|阿坝|甘孜|凉山|西昌|康定|'
    r'贵州|贵阳|六盘水|遵义|安顺|毕节|铜仁|黔西南|黔东南|黔南|云南|昆明|曲靖|玉溪|保山|昭通|丽江|普洱|临沧|楚雄|红河|文山|西双版纳|大理|德宏|怒江|迪庆|西藏|拉萨|日喀则|昌都|林芝|山南|那曲|'
    r'陕西|西安|铜川|宝鸡|咸阳|渭南|延安|汉中|榆林|安康|商洛|甘肃|兰州|嘉峪关|金昌|白银|天水|武威|张掖|平凉|酒泉|庆阳|定西|陇南|'
    r'青海|西宁|海东|海北|黄南|果洛|玉树|海西|宁夏|银川|石嘴山|吴忠|固原|中卫|新疆|乌鲁木齐|克拉玛依|吐鲁番|哈密|昌吉|博乐|库尔勒|阿克苏|阿图什|喀什|和田|伊宁|塔城|阿勒泰|石河子|阿拉尔|图木舒克|五家渠|北屯|铁门关|双河|可克达拉|昆玉|胡杨河|新星|白杨)',
    caseSensitive: false,
  );
  static final _internationalNodePattern = RegExp(
    r'(香港|澳门|台湾|新加坡|日本|美国|德国|英国|加拿大|澳大利亚|Hong Kong|Macao|Taiwan|Singapore|Japan|United States|Germany|United Kingdom|Canada|Australia|(^|[^A-Za-z])(HK|MO|TW|SG|JP|US|DE|UK|GB|CA|AU)([^A-Za-z]|$))',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    if (widget.proxyRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProxies());
    }
  }

  @override
  void dispose() {
    _client.close(force: true);
    super.dispose();
  }

  Future<void> _loadProxies() async {
    setState(() => _loading = true);
    try {
      final rememberedDelays = _decodeDelayResults(
        await _service.getDelayResults(),
      );
      final groupOrder = await _service.getProxyGroupOrder();
      final proxies = await _request('GET', const ['proxies']);
      final providerByNode = await _loadProviderNodeMap();

      final proxyMap = proxies['proxies'];
      final groups = <_ProxyGroup>[];

      if (proxyMap is Map) {
        for (final entry in proxyMap.entries) {
          final value = entry.value;
          if (value is! Map) continue;

          final all = value['all'];
          if (all is! List || all.isEmpty) continue;

          groups.add(
            _ProxyGroup(
              name: entry.key.toString(),
              type: value['type']?.toString() ?? 'Group',
              now: value['now']?.toString() ?? '',
              nodes: all.map((node) => node.toString()).toList(growable: false),
            ),
          );
        }
      }

      _sortGroupsByConfigOrder(groups, groupOrder);

      if (!mounted) return;
      setState(() {
        for (final entry in rememberedDelays.entries) {
          _delaysByNode.putIfAbsent(_nodeKey(entry.key), () => entry.value);
        }
        _groups = groups;
        _providerByNode
          ..clear()
          ..addAll(providerByNode);
      });
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAndTestAll() async {
    await _loadProxies();
    if (!mounted) return;
    await _testAllNodes();
  }

  Future<void> _testAllNodes() async {
    if (_testingAllNodes) return;
    if (!_groups.any(
      (group) => group.nodes.any((node) => _nodeKey(node).isNotEmpty),
    )) {
      return;
    }

    setState(() => _testingAllNodes = true);
    try {
      final testedNodes = <String>{};

      for (final group in _groups) {
        final groupNodes = <String>[];
        for (final node in group.nodes) {
          final key = _effectiveNodeName(node);
          if (key.isNotEmpty && testedNodes.add(key)) {
            groupNodes.add(key);
          }
        }

        for (final node in groupNodes) {
          await _testNodeDelay(node);
          if (!mounted) return;
        }
      }
    } finally {
      if (mounted) setState(() => _testingAllNodes = false);
    }
  }

  Future<void> _testGroupNodes(
    _ProxyGroup group, {
    required VoidCallback onProgress,
  }) async {
    final nodes = group.nodes
        .map(_effectiveNodeName)
        .where((node) => node.isNotEmpty)
        .toSet()
        .toList(growable: false);

    for (final node in nodes) {
      final test = _testNodeDelay(node);
      onProgress();
      await test;
      onProgress();
    }
  }

  Future<void> _testNodeDelay(String node) {
    final key = _effectiveNodeName(node);
    if (_testingNodes.contains(key)) {
      if (_delaysByNode[key]?.failed != true) return Future<void>.value();
      _testingNodes.remove(key);
    }
    final builtin = _builtinDelayResult(key);
    if (builtin != null) {
      if (mounted) setState(() => _delaysByNode[key] = builtin);
      return Future<void>.value();
    }
    _testingNodes.add(key);
    if (mounted) {
      setState(() {
        _delaysByNode[key] = const _DelayResult.testing();
      });
    }

    final queuedTest =
        _delayTestQueue.catchError((_) {}).then((_) => _runNodeDelayTest(key));
    _delayTestQueue = queuedTest;
    return queuedTest;
  }

  Future<void> _runNodeDelayTest(String key) async {
    try {
      final data = await _requestNodeDelay(
        node: key,
        url: _delayTestUrlForNode(key),
      );
      final delay = _asInt(data['delay']);
      if (!mounted) return;
      setState(() {
        _delaysByNode[key] =
            delay > 0 ? _DelayResult(delay) : _DelayResult.failed('测速失败');
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _delaysByNode[key] = _DelayResult.failed(_failureLabel(error)),
      );
    } finally {
      _testingNodes.remove(key);
      if (mounted) setState(() {});
      try {
        await _saveDelayResults();
      } catch (_) {
        // A persistence failure must not block this node's next delay test.
      }
    }
  }

  String _effectiveNodeName(String node) {
    var current = _nodeKey(node);
    final visited = <String>{};

    while (current.isNotEmpty && visited.add(current)) {
      _ProxyGroup? nestedGroup;
      for (final group in _groups) {
        if (_nodeKey(group.name) == current) {
          nestedGroup = group;
          break;
        }
      }
      if (nestedGroup == null || nestedGroup.now.isEmpty) return current;
      current = _nodeKey(nestedGroup.now);
    }
    return current;
  }

  _DelayResult? _delayForNode(String node) {
    return _delaysByNode[_effectiveNodeName(node)];
  }

  String _delayTestUrlForNode(String node) {
    if (node.toUpperCase() == 'DIRECT' || _cnNodePattern.hasMatch(node)) {
      return _directDelayTestUrl;
    }
    if (_internationalNodePattern.hasMatch(node)) {
      return _internationalDelayTestUrl;
    }
    return _proxyDelayTestUrl;
  }

  Future<Map<String, dynamic>> _requestNodeDelay({
    required String node,
    required String url,
  }) async {
    final query = <String, String>{
      'timeout': _delayTimeoutMs.toString(),
      'url': url,
    };
    final provider = _providerByNode[node];
    if (provider != null) {
      return _request(
        'GET',
        ['providers', 'proxies', provider, node, 'healthcheck'],
        queryParameters: query,
        responseTimeout: const Duration(milliseconds: _delayTimeoutMs + 1000),
      );
    }
    return _request(
      'GET',
      ['proxies', node, 'delay'],
      queryParameters: query,
      responseTimeout: const Duration(milliseconds: _delayTimeoutMs + 1000),
    );
  }

  Future<Map<String, String>> _loadProviderNodeMap() async {
    try {
      final data = await _request('GET', const ['providers', 'proxies']);
      final providers = data['providers'];
      if (providers is! Map) return const <String, String>{};

      final result = <String, String>{};
      for (final providerEntry in providers.entries) {
        final providerName = providerEntry.key.toString();
        final providerValue = providerEntry.value;
        if (providerValue is! Map) continue;

        final proxies = providerValue['proxies'];
        if (proxies is List) {
          for (final proxy in proxies) {
            final name = _providerProxyName(proxy);
            if (name != null) result[_nodeKey(name)] = providerName;
          }
        } else if (proxies is Map) {
          for (final proxyEntry in proxies.entries) {
            final name = _providerProxyName(proxyEntry.value) ??
                proxyEntry.key.toString();
            if (name.isNotEmpty) result[_nodeKey(name)] = providerName;
          }
        }
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  Future<void> _selectNode(
    _ProxyGroup group,
    String node, {
    VoidCallback? onChanged,
  }) async {
    if (!group.isManualSelectable) return;
    final previousNode = group.now;
    setState(() {
      _groups = [
        for (final item in _groups)
          item.name == group.name ? item.copyWith(now: node) : item,
      ];
      _delaysByNode[_effectiveNodeName(node)] = const _DelayResult.testing();
    });
    onChanged?.call();

    try {
      await _request(
        'PUT',
        ['proxies', group.name],
        body: <String, Object>{'name': node},
      );

      if (!mounted) return;
      await _testNodeDelay(node);
      onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _delaysByNode[_effectiveNodeName(node)] = _DelayResult.failed(
          _failureLabel(error),
        );
        _groups = [
          for (final item in _groups)
            item.name == group.name ? item.copyWith(now: previousNode) : item,
        ];
      });
      onChanged?.call();
      _showError(error);
    }
  }

  Future<void> _saveDelayResults() {
    _saveQueue = _saveQueue.catchError((_) {}).then(
          (_) => _service.setDelayResults(_encodeDelayResults(_delaysByNode)),
        );
    return _saveQueue;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    List<String> pathSegments, {
    Map<String, Object>? body,
    Map<String, String>? queryParameters,
    Duration responseTimeout = const Duration(seconds: 14),
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: 9090,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
    );

    final request =
        await _client.openUrl(method, uri).timeout(const Duration(seconds: 6));
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(responseTimeout);
    final text = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Controller ${response.statusCode}: ${text.trim()}');
    }

    if (text.trim().isEmpty) return const <String, dynamic>{};

    final decoded = jsonDecode(text);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return const <String, dynamic>{};
  }

  void _sortGroupsByConfigOrder(
    List<_ProxyGroup> groups,
    List<String> groupOrder,
  ) {
    final originalIndex = <String, int>{
      for (var index = 0; index < groups.length; index++)
        groups[index].name: index,
    };
    final orderIndex = <String, int>{
      for (var index = 0; index < groupOrder.length; index++)
        groupOrder[index]: index,
    };

    int rank(_ProxyGroup group) {
      if (_isGlobalGroup(group.name)) return 1 << 30;
      final configured = orderIndex[group.name];
      if (configured != null) return configured;
      return (1 << 29) + (originalIndex[group.name] ?? 0);
    }

    groups.sort((left, right) {
      final result = rank(left).compareTo(rank(right));
      if (result != 0) return result;
      return (originalIndex[left.name] ?? 0).compareTo(
        originalIndex[right.name] ?? 0,
      );
    });
  }

  void _showError(Object error) {
    showErrorNotice(context, error);
  }

  Future<void> _showNodes(_ProxyGroup group, Offset origin) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeight = screenSize.height * 0.72;
    final originAlignment = Alignment(
      (origin.dx / screenSize.width) * 2 - 1,
      (origin.dy / screenSize.height) * 2 - 1,
    );
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭代理组',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.72, end: 1).animate(curved),
            alignment: originAlignment,
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        var testingGroup = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final colors = Theme.of(context).colorScheme;
            return SafeArea(
              child: Center(
                child: Dialog(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      maxHeight: maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      group.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${group.type.toUpperCase()} · ${group.selectedIndex}/${group.nodes.length}',
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '测速当前代理组',
                                onPressed: _testingAllNodes || testingGroup
                                    ? null
                                    : () async {
                                        setModalState(
                                          () => testingGroup = true,
                                        );
                                        try {
                                          await _testGroupNodes(
                                            group,
                                            onProgress: () {
                                              if (context.mounted) {
                                                setModalState(() {});
                                              }
                                            },
                                          );
                                        } finally {
                                          if (context.mounted) {
                                            setModalState(
                                              () => testingGroup = false,
                                            );
                                          }
                                        }
                                      },
                                icon: testingGroup
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.speed_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Flexible(
                            child: GridView.builder(
                              shrinkWrap: true,
                              itemCount: group.nodes.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 2.35,
                              ),
                              itemBuilder: (context, index) {
                                final liveGroup = _groups.firstWhere(
                                  (item) => item.name == group.name,
                                  orElse: () => group,
                                );
                                final node = group.nodes[index];
                                final selected = node == liveGroup.now;
                                return _NodeButton(
                                  name: node,
                                  delay: _delayForNode(node),
                                  selected: selected,
                                  onTap: liveGroup.isManualSelectable
                                      ? () {
                                          unawaited(
                                            _selectNode(
                                              liveGroup,
                                              node,
                                              onChanged: () {
                                                if (context.mounted) {
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          );
                                        }
                                      : null,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _testingAllNodes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('代理面板'),
        actions: [
          IconButton(
            tooltip: '全部测速',
            onPressed: widget.proxyRunning && !busy ? _refreshAndTestAll : null,
            icon: _testingAllNodes
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_rounded),
          ),
        ],
      ),
      body: !widget.proxyRunning
          ? const _StoppedHint()
          : _ProxyTab(
              groups: _groups,
              delayForNode: _delayForNode,
              loading: _loading,
              onRefresh: _loadProxies,
              onGroupTap: _showNodes,
            ),
    );
  }
}

class _ProxyGroup {
  const _ProxyGroup({
    required this.name,
    required this.type,
    required this.now,
    required this.nodes,
  });

  final String name;
  final String type;
  final String now;
  final List<String> nodes;

  bool get isManualSelectable => type.trim().toLowerCase() == 'selector';

  int get selectedIndex {
    final index = nodes.indexOf(now);
    return index < 0 ? 0 : index + 1;
  }

  _ProxyGroup copyWith({String? now}) {
    return _ProxyGroup(
      name: name,
      type: type,
      now: now ?? this.now,
      nodes: nodes,
    );
  }
}

class _DelayResult {
  const _DelayResult(this.ms)
      : testing = false,
        failed = false,
        failureLabel = '超时';

  const _DelayResult.testing()
      : ms = null,
        testing = true,
        failed = false,
        failureLabel = '超时';

  const _DelayResult.failed([this.failureLabel = '超时'])
      : ms = null,
        testing = false,
        failed = true;

  final int? ms;
  final bool testing;
  final bool failed;
  final String failureLabel;
}

class _ProxyTab extends StatelessWidget {
  const _ProxyTab({
    required this.groups,
    required this.delayForNode,
    required this.loading,
    required this.onRefresh,
    required this.onGroupTap,
  });

  final List<_ProxyGroup> groups;
  final _DelayResult? Function(String) delayForNode;
  final bool loading;
  final Future<void> Function() onRefresh;
  final void Function(_ProxyGroup group, Offset origin) onGroupTap;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (loading && groups.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (groups.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyGroups(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              sliver: SliverGrid.builder(
                itemCount: groups.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.35,
                ),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _ProxyGroupButton(
                    group: group,
                    delay: delayForNode(group.now),
                    onTap: (origin) => onGroupTap(group, origin),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ProxyGroupButton extends StatelessWidget {
  const _ProxyGroupButton({
    required this.group,
    required this.delay,
    required this.onTap,
  });

  final _ProxyGroup group;
  final _DelayResult? delay;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    var tapOrigin = MediaQuery.sizeOf(context).center(Offset.zero);

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTapDown: (details) => tapOrigin = details.globalPosition,
        onTap: () => onTap(tapOrigin),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.now.isEmpty ? '未选择' : group.now,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DelayBadge(delay: delay),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeButton extends StatelessWidget {
  const _NodeButton({
    required this.name,
    required this.delay,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final _DelayResult? delay;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        selected ? colors.primary : colors.surfaceContainerHighest;
    final foreground = selected ? colors.onPrimary : colors.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _DelayText(delay: delay, selected: selected),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.flash_on_rounded,
                    size: 19,
                    color:
                        selected ? colors.onPrimary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DelayBadge extends StatelessWidget {
  const _DelayBadge({required this.delay});

  final _DelayResult? delay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = _delayLabel(delay);
    if (text == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _delayColor(colors, delay),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DelayText extends StatelessWidget {
  const _DelayText({required this.delay, required this.selected});

  final _DelayResult? delay;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = _delayLabel(delay) ?? '未测速';
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected ? colors.onPrimary : _delayColor(colors, delay),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _StoppedHint extends StatelessWidget {
  const _StoppedHint();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.power_settings_new_rounded,
                  size: 42,
                  color: colors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  '请先启动代理',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '代理面板需要连接本机 mihomo controller 后才能读取代理组和测速。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 42, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              '没有可选择的代理组',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '当前配置可能没有 selector、url-test 或 fallback 等代理组。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _nodeKey(String node) => node.trim();

String? _providerProxyName(Object? value) {
  if (value is Map) {
    final name = value['name'];
    if (name != null && name.toString().isNotEmpty) return name.toString();
    final proxyName = value['proxyName'];
    if (proxyName != null && proxyName.toString().isNotEmpty) {
      return proxyName.toString();
    }
    return null;
  }
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

_DelayResult? _builtinDelayResult(String node) {
  return switch (node.trim().toUpperCase()) {
    'REJECT' => const _DelayResult.failed('拒绝'),
    'REJECT-DROP' => const _DelayResult.failed('丢弃'),
    'PASS' || 'COMPATIBLE' => const _DelayResult.failed('不适用'),
    _ => null,
  };
}

bool _isGlobalGroup(String name) => name.trim().toLowerCase() == 'global';

Map<String, _DelayResult> _decodeDelayResults(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['version'] != 1) {
      return const <String, _DelayResult>{};
    }
    final saved = decoded['results'];
    if (saved is! Map) return const <String, _DelayResult>{};

    final results = <String, _DelayResult>{};
    for (final entry in saved.entries) {
      final node = _nodeKey(entry.key.toString());
      final value = _asInt(entry.value);
      if (node.isEmpty || value < 0) continue;
      results[node] = _DelayResult(value);
    }
    return results;
  } catch (_) {
    return const <String, _DelayResult>{};
  }
}

String _encodeDelayResults(Map<String, _DelayResult> delays) {
  final values = <String, int>{};
  for (final entry in delays.entries) {
    final delay = entry.value;
    if (delay.testing) continue;
    if (delay.failed) continue;
    final ms = delay.ms;
    if (ms != null) values[entry.key] = ms;
  }
  return jsonEncode(<String, Object>{'version': 1, 'results': values});
}

String? _delayLabel(_DelayResult? delay) {
  if (delay == null) return null;
  if (delay.testing) return '测速中';
  if (delay.failed) return delay.failureLabel;
  final ms = delay.ms;
  return ms == null ? null : '${ms}ms';
}

String _failureLabel(Object error) {
  if (error is TimeoutException) return '超时';
  if (error is SocketException) return '连接失败';

  final text = error.toString().toLowerCase();
  final targetHttp = RegExp(
    r'(?:status code[: ]+|http[/ ]?)(\d{3})',
  ).firstMatch(text);
  if (targetHttp != null) return 'HTTP ${targetHttp.group(1)}';
  final http = RegExp(r'controller (\d{3})').firstMatch(text);
  if (http != null) return 'HTTP ${http.group(1)}';
  if (text.contains('408') ||
      text.contains('504') ||
      text.contains('timeout') ||
      text.contains('deadline exceeded')) {
    return '超时';
  }
  if (text.contains('connection') || text.contains('socket')) return '连接失败';
  if (text.contains('format') || text.contains('json')) return '响应异常';
  return '响应异常';
}

Color _delayColor(ColorScheme colors, _DelayResult? delay) {
  if (delay == null || delay.testing) return colors.onSurfaceVariant;
  if (delay.failed) return colors.error;
  final ms = delay.ms ?? 9999;
  if (ms <= 250) return const Color(0xFF36A269);
  if (ms <= 800) return const Color(0xFFB78018);
  return colors.error;
}
