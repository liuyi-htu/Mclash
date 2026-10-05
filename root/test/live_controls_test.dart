import 'package:mclash/shared/pulse_dashboard.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/main.dart';
import 'package:mclash/pages/proxy_panel_page.dart';

class _Controller extends HttpOverrides {
  final writes = <Map<String, Object>>[];
  String mode = 'rule';
  int failedModeReads = 0;
  bool failPersistence = false;
  Completer<Map<String, Object>>? pendingModeRead;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);

  Map<String, Object> respond(String method, Uri url, String body) {
    if (method == 'PATCH' || method == 'PUT') {
      writes
          .add({'method': method, 'path': url.path, 'body': jsonDecode(body)});
      if (method == 'PATCH' && url.path == '/configs') {
        mode = (jsonDecode(body) as Map)['mode'] as String;
      }
      return {};
    }
    if (url.path == '/configs') {
      if (failedModeReads > 0) {
        failedModeReads--;
        throw const SocketException('controller not ready');
      }
      return {'mode': mode};
    }
    if (url.path == '/proxies') {
      return {
        'proxies': {
          'Node A': {
            'type': 'VMess',
            'server': 'exit.example',
            'port': 443,
            'dialer-proxy': 'Front',
            'uuid': 'private-credential'
          },
          'Node B': {'type': 'Http', 'server': 'other.example', 'port': 80},
          'Front': {'type': 'Socks5'},
          'Test group': {
            'type': 'Selector',
            'now': 'Node A',
            'all': ['Node A', 'Node B'],
          },
        },
      };
    }
    if (url.path.endsWith('/delay')) return {'delay': 50};
    return {};
  }
}

class _Client extends Fake implements HttpClient {
  _Client(this.controller);
  final _Controller controller;
  @override
  set connectionTimeout(Duration? timeout) {}
  @override
  set findProxy(String Function(Uri)? callback) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(controller, method, url);
  @override
  void close({bool force = false}) {}
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  set contentType(ContentType? type) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.controller, this.method, this.url);
  final _Controller controller;
  @override
  final String method;
  final Uri url;
  final body = StringBuffer();
  @override
  final headers = _Headers();
  @override
  void write(Object? value) => body.write(value);
  @override
  Future<HttpClientResponse> close() async {
    if (method == 'GET' &&
        url.path == '/configs' &&
        controller.pendingModeRead != null) {
      return _Response(await controller.pendingModeRead!.future);
    }
    return _Response(controller.respond(method, url, body.toString()));
  }
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.data);
  final Map<String, Object> data;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(utf8.encode(jsonEncode(data))).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Set<String> selectedMode(WidgetTester tester) {
  final mode =
      tester.widget<PulseModeControl>(find.byType(PulseModeControl)).mode;
  return mode == null ? {} : {mode};
}

void main() {
  const channel = MethodChannel('mclash/native');
  late _Controller controller;
  HttpOverrides? previous;
  var running = true;
  final rememberedModes = <String>[];
  final nativeCalls = <String>[];

  setUp(() {
    running = true;
    rememberedModes.clear();
    nativeCalls.clear();
    previous = HttpOverrides.current;
    controller = _Controller();
    HttpOverrides.global = controller;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      if (call.method == 'rememberProxyMode') {
        if (controller.failPersistence) throw StateError('storage unavailable');
        rememberedModes.add(call.arguments['mode'] as String);
      }
      return switch (call.method) {
        'getUsageNoticeAccepted' => true,
        'getDeveloperModeEnabled' => false,
        'getConfigInfo' => <String, Object?>{'exists': true},
        'getProxyStatus' => running ? 'running' : 'stopped',
        'isRunning' => running,
        'getDebugLoggingEnabled' => false,
        'getTrafficStats' => <String, int>{'rxBytes': 0, 'txBytes': 0},
        'getDelayResults' => '{}',
        'getProxyGroupOrder' => <String>[],
        _ => null,
      };
    });
  });

  tearDown(() {
    HttpOverrides.global = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('open panel follows an external stop and reconnect',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('代理'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ProxyPanelPage>(find.byType(ProxyPanelPage)).proxyRunning,
        true);
    running = false;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ProxyPanelPage>(find.byType(ProxyPanelPage)).proxyRunning,
        false);
    running = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ProxyPanelPage>(find.byType(ProxyPanelPage)).proxyRunning,
        true);
    expect(find.text('Test group'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'expanded selector shows only one line for chain or selected node',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ProxyPanelPage(proxyRunning: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test group'));
    await tester.pumpAndSettle();
    expect(find.text('SELECT · 1/2'), findsOneWidget);
    expect(find.text('Front → Node A'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Front → Node A')).maxLines, 1);
    expect(find.textContaining('服务器：'), findsNothing);
    expect(find.textContaining('来源：'), findsNothing);
    expect(find.textContaining('选择路径：'), findsNothing);
    expect(find.textContaining('private-credential'), findsNothing);
    await tester.tap(find.text('Node B').last);
    await tester.pumpAndSettle();
    expect(find.text('SELECT · 2/2'), findsOneWidget);
    expect(find.text('Front → Node A'), findsNothing);
    expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('Node B')),
        findsNWidgets(2));
    expect(find.textContaining('服务器：'), findsNothing);
    expect(controller.writes.single['body'], {'name': 'Node B'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'proxy panel adapts to tablet rotation, split screen and large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data:
            MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
        child: child!,
      ),
      home: const ProxyPanelPage(proxyRunning: true),
    ));
    await tester.pumpAndSettle();
    final groups = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
        (groups.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        greaterThan(2));
    await tester.tap(find.text('Test group'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Dialog)).width, greaterThan(520));
    var nodes = tester.widget<GridView>(find.byType(GridView));
    expect(
        (nodes.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        greaterThan(2));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(800, 1200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(360, 800);
    await tester.pumpAndSettle();
    nodes = tester.widget<GridView>(find.byType(GridView));
    expect(
        (nodes.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Node B').last);
    await tester.pumpAndSettle();
    expect(controller.writes.last['body'], {'name': 'Node B'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('running proxy can switch global, direct and rule modes',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    for (final label in ['全局', '直连', '规则']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    expect(rememberedModes, containsAllInOrder(['global', 'direct', 'rule']));
    expect(controller.writes, [
      {
        'method': 'PATCH',
        'path': '/configs',
        'body': {'mode': 'global'}
      },
      {
        'method': 'PATCH',
        'path': '/configs',
        'body': {'mode': 'direct'}
      },
      {
        'method': 'PATCH',
        'path': '/configs',
        'body': {'mode': 'rule'}
      },
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dashboard mode is remembered when the app reopens',
      (tester) async {
    controller.mode = 'global';
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    expect(rememberedModes, contains('global'));
    expect(selectedMode(tester), {'global'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'reopening with a continuously running service retries mode reads',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    expect(selectedMode(tester), {'rule'});
    await tester.pumpWidget(const SizedBox());
    controller.mode = 'global'; // Dashboard changes the still-running core.
    controller.failedModeReads = 2;
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    expect(selectedMode(tester), isNot(contains('rule')));
    expect(selectedMode(tester), isEmpty);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    expect(selectedMode(tester), {'global'});
    expect(controller.mode, 'global');
    expect(controller.writes, isEmpty);
    expect(nativeCalls, isNot(contains('start')));
    expect(nativeCalls, isNot(contains('restart')));
    expect(nativeCalls, isNot(contains('stop')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('foreground polling reflects dashboard edits without restarting',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    for (final mode in ['global', 'direct', 'rule']) {
      controller.mode = mode;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(selectedMode(tester), {mode});
    }
    expect(controller.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live mode remains visible when persistence fails',
      (tester) async {
    controller.mode = 'direct';
    controller.failPersistence = true;
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    expect(selectedMode(tester), {'direct'});
    expect(selectedMode(tester), isNot(contains('rule')));
    expect(controller.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a late mode read cannot undo the user selection',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    controller.pendingModeRead = Completer<Map<String, Object>>();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.tap(find.text('全局'));
    await tester.pumpAndSettle();
    controller.pendingModeRead!.complete({'mode': 'rule'});
    controller.pendingModeRead = null;
    await tester.pumpAndSettle();
    expect(selectedMode(tester), {'global'});
    expect(controller.mode, 'global');
    expect(rememberedModes.last, 'global');
    expect(controller.writes.single['body'], {'mode': 'global'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a successful core mode change survives a persistence failure',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    controller.failPersistence = true;
    await tester.tap(find.text('全局'));
    await tester.pumpAndSettle();
    expect(selectedMode(tester), {'global'});
    expect(controller.mode, 'global');
    expect(controller.writes.single['body'], {'mode': 'global'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid controller mode is not normalized to rule',
      (tester) async {
    controller.mode = 'invalid';
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    expect(selectedMode(tester), isNot(contains('rule')));
    expect(rememberedModes, isEmpty);
    expect(find.text('选择运行模式'), findsNothing);
    expect(selectedMode(tester), isEmpty);
    expect(controller.writes, isEmpty);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('running proxy can select a node in a selector group',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ProxyPanelPage(proxyRunning: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Node B').last);
    await tester.pumpAndSettle();
    expect(controller.writes, [
      {
        'method': 'PUT',
        'path': '/proxies/Test%20group',
        'body': {'name': 'Node B'}
      },
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
