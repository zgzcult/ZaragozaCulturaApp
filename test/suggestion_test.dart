import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/suggestion.dart';

class _FakeClient extends SubmissionClient {
  final SubmitResult result;
  final List<Map<String, String>> sent = [];

  _FakeClient(this.result);

  @override
  Future<SubmitResult> send({
    required String type,
    required String title,
    required String description,
    String contact = '',
  }) async {
    sent.add({
      'type': type,
      'title': title,
      'description': description,
      'contact': contact,
    });
    return result;
  }
}

Widget _app(_FakeClient client) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SuggestionScreen(client: client),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('enviar una mejora manda tipo, título y descripción', (
    tester,
  ) async {
    final client = _FakeClient(SubmitResult.ok);
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(_app(client));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Título de la mejora'),
      'Modo oscuro',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descripción'),
      'Sería genial poder usar la app de noche.',
    );
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(client.sent, hasLength(1));
    expect(client.sent.single['type'], 'mejora');
    expect(client.sent.single['title'], 'Modo oscuro');
    expect(
      client.sent.single['description'],
      'Sería genial poder usar la app de noche.',
    );
    expect(
      find.text('¡Gracias! Hemos recibido tu sugerencia.'),
      findsOneWidget,
    );
    expect(
      find.text('Sugerir mejoras'),
      findsNothing,
    ); // vuelve a la pantalla anterior

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('no envía si faltan título o descripción', (tester) async {
    final client = _FakeClient(SubmitResult.ok);
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(_app(client));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(client.sent, isEmpty);
    expect(find.textContaining('Escribe un título'), findsOneWidget);
    expect(find.textContaining('Cuéntanos un poco más'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('si falla el envío se avisa y se conserva lo escrito', (
    tester,
  ) async {
    final client = _FakeClient(SubmitResult.unavailable);
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(_app(client));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Título de la mejora'),
      'Modo oscuro',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Descripción'),
      'Sería genial poder usar la app de noche.',
    );
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No se pudo enviar. Comprueba tu conexión'),
      findsOneWidget,
    );
    expect(find.text('Modo oscuro'), findsOneWidget); // sigue en pantalla
    expect(find.text('Enviar'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'la ficha de una actividad del Ayuntamiento lleva el aviso de origen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final event = CulturalEvent(
        id: 'e1',
        title: 'Concierto de prueba',
        description: 'Descripción de la actividad.',
        category: CulturalCategory.musica,
        date: '2026-10-10',
        time: '20:00',
        place: 'Auditorio',
        officialUrl: 'https://www.zaragoza.es',
        timeSlots: const ['20:00'],
        updatedAt: '2026-10-05',
      );
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: event,
            isFavorite: false,
            onToggleFavorite: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Concierto de prueba'), findsOneWidget);
      expect(
        find.text(
          'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de '
          'Cultura). Información actualizada por última vez el 5 de octubre '
          'de 2026.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('elaboración de esta aplicación'),
        findsNothing,
      );

      await tester.binding.setSurfaceSize(null);
    },
  );
}
