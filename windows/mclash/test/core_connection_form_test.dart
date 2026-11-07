import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mclash/core_connection_settings.dart';
import 'package:mclash/core_connection_form.dart';

void main() {
  testWidgets('edits all three values, masks secret, and saves only explicitly',
      (tester) async {
    CoreConnectionSettings? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => CoreConnectionForm(
                            initial:
                                const CoreConnectionSettings(mixedPort: 17890),
                            onSave: (value) async => saved = value)),
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '0.0.0.0:9191');
    await tester.enterText(fields.at(1), 'local-test-secret');
    await tester.enterText(fields.at(2), '7891');
    expect(tester.widget<TextField>(fields.at(1)).obscureText, true);
    expect(saved, isNull);
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved!.controller, '0.0.0.0:9191');
    expect(saved!.secret, 'local-test-secret');
    expect(saved!.mixedPort, 7891);
    expect(find.byType(CoreConnectionForm), findsNothing);
  });
}
