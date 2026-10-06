import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('La pantalla principal saluda y ofrece los accesos', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZaragozaCulturaApp());
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'Buen(os|as) ')), findsOneWidget);
    for (final label in [
      'Agenda',
      'Para hoy',
      'Monumentos',
      'Rutas',
      'Servicios',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Agenda abre la agenda y se puede volver al inicio', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZaragozaCulturaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);

    await tester.tap(find.byTooltip('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('Monumentos'), findsOneWidget);
  });
}
