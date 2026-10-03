import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/shared/add_action_button.dart';

void main() {
  testWidgets('management add buttons align with the configuration tab',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final size in [
      const Size(390, 844),
      const Size(1024, 1366),
      const Size(390, 480),
    ]) {
      for (final bottomPadding in [0.0, 24.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: bottomPadding);
        tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
        for (final navigationHeight in [80.0, 64.0]) {
          final theme = ThemeData(
              useMaterial3: true,
              navigationBarTheme:
                  NavigationBarThemeData(height: navigationHeight));
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
              bottomNavigationBar: NavigationBar(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: '首页'),
                  NavigationDestination(
                      icon: Icon(Icons.settings), label: '配置'),
                ],
              ),
              body: Scaffold(
                floatingActionButton: PopupMenuButton<String>(
                  itemBuilder: (_) => const [],
                  child: const AddActionIcon(),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          final expected = tester.getCenter(find.byType(AddActionIcon));
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => Scaffold(
                floatingActionButtonLocation:
                    managementAddButtonLocation(context),
                floatingActionButton: AddActionButton(
                  tooltip: '新增',
                  onPressed: () {},
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          final actual = tester.getCenter(find.byType(AddActionIcon));
          expect(actual.dx, closeTo(expected.dx, 0.01));
          expect(actual.dy, closeTo(expected.dy, 0.01));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });
}
