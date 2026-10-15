import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/config_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_platform_service.dart';

class _Service implements ProxyPlatformService {
  _Service(this.read);
  final List<Map<String, Object>> Function() read;
  @override
  Future<List<ConfigProfile>> getConfigs() async =>
      read().map(ConfigProfile.fromMap).toList();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object> _profile(int id, String type) => {
      'id': '$id',
      'name': '配置$id',
      'type': type,
      'active': true,
      'exists': true,
      'updatedAt': 0,
      if (type == 'subscription') ...{
        'url': 'https://example.org/sub$id',
        'subscriptionNames': {'https://example.org/sub$id': '机场$id'},
      },
    };

void main() {
  for (final count in [0, 1, 2]) {
    testWidgets(
        'airport config count $count routes add to creation or management',
        (tester) async {
      var profiles = [
        {..._profile(0, 'local'), 'active': count < 2},
        for (var i = 1; i <= count; i++)
          {..._profile(i, 'subscription'), 'active': count == 2 && i == 2},
      ];
      final service = _Service(() => profiles);
      await tester.pumpWidget(
          MaterialApp(home: ConfigPage(proxyRunning: false, service: service)));
      await tester.pumpAndSettle();
      Future<void> checkMenu(bool enabled) async {
        await tester.tap(find.byTooltip('添加配置'));
        await tester.pumpAndSettle();
        final airport = tester.widget<PopupMenuItem<dynamic>>(find.ancestor(
            of: find.text('添加机场配置'),
            matching:
                find.byWidgetPredicate((widget) => widget is PopupMenuItem)));
        final local = tester.widget<PopupMenuItem<dynamic>>(find.ancestor(
            of: find.text('添加本地配置'),
            matching:
                find.byWidgetPredicate((widget) => widget is PopupMenuItem)));
        expect(airport.enabled, enabled);
        expect(local.enabled, isTrue);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }

      await checkMenu(true);
      await tester.tap(find.byTooltip('添加配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加机场配置'));
      await tester.pumpAndSettle();
      if (count == 0) {
        expect(find.text('添加机场订阅'), findsOneWidget);
        expect(find.widgetWithText(TextField, '配置名称'), findsNothing);
        await tester.tapAt(const Offset(5, 5));
      } else {
        expect(find.text('订阅管理'), findsOneWidget);
        expect(find.text('机场${count == 2 ? 2 : 1}'), findsOneWidget);
        expect(find.text('添加机场订阅'), findsNothing);
        await tester.tap(find.byTooltip('添加机场'));
        await tester.pumpAndSettle();
        expect(find.text('添加机场'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      // Simulate removing the remaining subscriptions, then refresh the list.
      profiles = [_profile(0, 'local')];
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      await checkMenu(true);
      await tester.tap(find.byTooltip('添加配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加机场配置'));
      await tester.pumpAndSettle();
      expect(find.text('添加机场订阅'), findsOneWidget);
      expect(find.widgetWithText(TextField, '配置名称'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });
  }
}
