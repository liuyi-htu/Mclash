import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/add_action_button.dart';
import 'package:mclash/config_management_page.dart';
import 'package:mclash/models.dart';
import 'package:mclash/proxy_edit_access.dart';
import 'package:mclash/subscription_management_page.dart';

void main() {
  testWidgets('subscription writes follow live state without closing page',
      (tester) async {
    final status = ValueNotifier(ProxyStatus.stopped);
    const profile = ConfigProfile(
        id: 'test',
        name: 'Test',
        type: 'subscription',
        url: 'https://example.com/sub',
        active: true,
        exists: true,
        updatedAt: 0);
    var updates = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProxyEditAccess.wrap(
            status,
            (_) => SubscriptionManagementPage(
                profile: profile,
                proxyRunning: false,
                onEdit: (_, unused) async => profile,
                onReorder: (_, unused) async => profile,
                onUpdate: (_, unused) async {
                  updates++;
                  return profile;
                }))));
    await tester.pumpAndSettle();
    final update = find.byIcon(Icons.refresh_rounded);
    expect(
        tester
            .widget<IconButton>(
                find.ancestor(of: update, matching: find.byType(IconButton)))
            .onPressed,
        isNotNull);
    for (final next in [
      ProxyStatus.running,
      ProxyStatus.starting,
      ProxyStatus.failed
    ]) {
      status.value = next;
      await tester.pump();
      expect(find.text('订阅管理'), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(
                  find.ancestor(of: update, matching: find.byType(IconButton)))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<AddActionButton>(find.byType(AddActionButton))
              .onPressed,
          isNull);
    }
    status.value = ProxyStatus.stopped;
    await tester.pump();
    await tester.tap(update);
    await tester.pumpAndSettle();
    expect(updates, 1);
    await tester.pumpWidget(const SizedBox());
    status.dispose();
  });

  testWidgets('open rule dialog disables save when service starts',
      (tester) async {
    final status = ValueNotifier(ProxyStatus.stopped);
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: ProxyEditAccess.wrap(
            status,
            (_) => ConfigManagementPage(
                content: 'rules:\n  - MATCH,DIRECT\n',
                mode: ConfigManagementMode.rules,
                onSave: (_) async {
                  saves++;
                }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MATCH,DIRECT'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNotNull);
    status.value = ProxyStatus.running;
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull);
    expect(saves, 0);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(
        tester.widget<AddActionButton>(find.byType(AddActionButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    status.dispose();
  });
}
