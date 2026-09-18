import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Shows the Zaragoza cultural agenda', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZaragozaCulturaApp());
    await tester.pumpAndSettle();

    expect(find.text('Zaragoza Cultura'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
  });
}
