import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('La pantalla principal ofrece los tres accesos', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZaragozaCulturaApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Bienvenid@ a'), findsOneWidget);
    expect(find.textContaining('Maña Zaragoza'), findsOneWidget);
    expect(find.text('Actividades'), findsOneWidget);
    expect(find.text('Restaurantes'), findsOneWidget);
    expect(find.text('Sugerencia del día'), findsOneWidget);
  });

  testWidgets('Actividades abre la agenda y se puede volver al inicio', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZaragozaCulturaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Actividades'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);

    await tester.tap(find.byTooltip('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Restaurantes'), findsOneWidget);
  });
}
