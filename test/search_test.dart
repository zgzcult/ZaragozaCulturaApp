import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';

String _key(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

CulturalEvent _event(
  String id,
  String title,
  int daysFromNow, {
  String place = 'Sala de conciertos',
  String description = '',
  CulturalCategory category = CulturalCategory.musica,
}) {
  return CulturalEvent(
    id: id,
    title: title,
    description: description,
    category: category,
    date: _key(DateTime.now().add(Duration(days: daysFromNow))),
    time: '20:00',
    place: place,
    officialUrl: 'https://www.zaragoza.es',
    timeSlots: const ['20:00'],
  );
}

class _FakeRepository extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _FakeRepository(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

void main() {
  final today = DateTime(2026, 10, 5);

  CulturalEvent at(
    String id,
    String title,
    String date, {
    String place = 'Sala',
    String description = '',
  }) {
    return CulturalEvent(
      id: id,
      title: title,
      description: description,
      category: CulturalCategory.musica,
      date: date,
      time: '20:00',
      place: place,
      officialUrl: 'https://www.zaragoza.es',
      timeSlots: const ['20:00'],
    );
  }

  group('searchEvents', () {
    test(
      'una actividad con muchas fechas sale una vez, con la más próxima',
      () {
        final results = searchEvents(
          [
            at('3', 'Noche de jazz', '2026-10-20'),
            at('1', 'Noche de jazz', '2026-10-08'),
            at('2', 'Noche de jazz', '2026-10-12'),
          ],
          'jazz',
          today: today,
        );
        expect(results, hasLength(1));
        expect(results.first.event.date, '2026-10-08');
        expect(results.first.otherDates, 2);
      },
    );

    test('ignora mayúsculas y tildes', () {
      final results = searchEvents(
        [at('1', 'Música en el Patio', '2026-10-08')],
        'MUSICA patio',
        today: today,
      );
      expect(results, hasLength(1));
    });

    test('exige todas las palabras', () {
      final events = [at('1', 'Noche de jazz', '2026-10-08')];
      expect(searchEvents(events, 'jazz noche', today: today), hasLength(1));
      expect(searchEvents(events, 'jazz teatro', today: today), isEmpty);
    });

    test('no muestra fechas pasadas', () {
      final results = searchEvents(
        [
          at('1', 'Concierto', '2026-10-01'),
          at('2', 'Concierto', '2026-10-09'),
        ],
        'concierto',
        today: today,
      );
      expect(results.single.event.date, '2026-10-09');
      expect(results.single.otherDates, 0);
      expect(
        searchEvents(
          [at('1', 'Concierto', '2026-10-01')],
          'concierto',
          today: today,
        ),
        isEmpty,
      );
    });

    test('mismo título en lugares distintos son actividades distintas', () {
      final results = searchEvents(
        [
          at('1', 'Concierto', '2026-10-08', place: 'Auditorio'),
          at('2', 'Concierto', '2026-10-09', place: 'Teatro Principal'),
        ],
        'concierto',
        today: today,
      );
      expect(results, hasLength(2));
    });

    test('busca por lugar, categoría y descripción; el título va primero', () {
      final results = searchEvents(
        [
          at(
            '1',
            'Otra cosa',
            '2026-10-08',
            description: 'Habrá goya por todas partes',
          ),
          at('2', 'Visita a Goya', '2026-10-09'),
          at('3', 'Ruta', '2026-10-07', place: 'Museo de Goya'),
        ],
        'goya',
        today: today,
      );
      expect(results.map((r) => r.event.id), ['2', '3', '1']);
    });

    test('búsqueda vacía no devuelve nada', () {
      expect(
        searchEvents([at('1', 'Jazz', '2026-10-08')], '   ', today: today),
        isEmpty,
      );
    });
  });

  testWidgets(
    'Pestaña Buscar: escribir muestra una sola tarjeta por actividad',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _FakeRepository([
        _event('a1', 'Noche de jazz', 1),
        _event('a2', 'Noche de jazz', 3),
        _event('a3', 'Noche de jazz', 6),
        _event('b1', 'Obra de teatro', 2, category: CulturalCategory.teatro),
      ]);

      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(ZaragozaCulturaApp(repository: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actividades'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escribe lo que buscas'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'jazz');
      await tester.pumpAndSettle();

      expect(find.text('Noche de jazz'), findsOneWidget);
      expect(find.text('Obra de teatro'), findsNothing);
      expect(find.textContaining('Mañana ·'), findsOneWidget);
      expect(find.textContaining('y 2 fechas más'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hay actividades que coincidan'),
        findsOneWidget,
      );

      await tester.binding.setSurfaceSize(null);
    },
  );
}
