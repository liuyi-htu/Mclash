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

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);

  Map<String, Object> respond(String method, Uri url, String body) {
    if (method == 'PATCH' || method == 'PUT') {
      writes
          .add({'method': method, 'path': url.path, 'body': jsonDecode(body)});
      return {};
    }
    if (url.path == '/configs') return {'mode': 'rule'};
    if (url.path == '/proxies') {
      return {
        'proxies': {
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
  Future<HttpClientResponse> close() async =>
      _Response(controller.respond(method, url, body.toString()));
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

void main() {
  const channel = MethodChannel('mclash/native');
  late _Controller controller;
  HttpOverrides? previous;

  setUp(() {
    previous = HttpOverrides.current;
    controller = _Controller();
    HttpOverrides.global = controller;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getUsageNoticeAccepted' => true,
        'getDeveloperModeEnabled' => false,
        'getConfigInfo' => <String, Object?>{'exists': true},
        'getProxyStatus' => 'running',
        'isRunning' => true,
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

  testWidgets('running proxy can switch global, direct and rule modes',
      (tester) async {
    await tester.pumpWidget(const MclashApp());
    await tester.pumpAndSettle();
    for (final label in ['全局模式', '直连模式', '规则模式']) {
      await tester.tap(find.text('代理规则'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
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

  testWidgets('running proxy can select a node in a selector group',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ProxyPanelPage(proxyRunning: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Node B'));
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
