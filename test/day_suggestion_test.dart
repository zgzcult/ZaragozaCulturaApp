import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/day_suggestion.dart';
import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';

// Miércoles 7 de octubre de 2026, 17:00.
final _now = DateTime(2026, 10, 7, 17, 0);
const _today = '2026-10-07';

CulturalEvent _event(
  String id,
  String title, {
  CulturalCategory category = CulturalCategory.musica,
  List<String> slots = const [],
  String date = _today,
  String runStart = '',
  String runEnd = '',
}) {
  return CulturalEvent(
    id: id,
    title: title,
    description: '',
    category: category,
    date: date,
    time: slots.isEmpty ? '' : slots.first.split('–').first,
    place: 'Sala',
    officialUrl: 'https://www.zaragoza.es',
    timeSlots: slots,
    runStart: runStart,
    runEnd: runEnd,
  );
}

class _Repo extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _Repo(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

void main() {
  group('¿Se puede asistir todavía?', () {
    test('actividad de otro día: no', () {
      expect(
        availabilityOf(
          _event('a', 'x', date: '2026-10-08', slots: ['20:00']),
          _now,
        ),
        Availability.finished,
      );
    });

    test('empieza más tarde: próxima', () {
      expect(
        availabilityOf(_event('a', 'x', slots: ['19:00']), _now),
        Availability.upcoming,
      );
    });

    test('ya ha terminado: no', () {
      expect(
        availabilityOf(_event('a', 'x', slots: ['10:00–14:00']), _now),
        Availability.finished,
      );
    });

    test('en curso ahora: sí', () {
      expect(
        availabilityOf(_event('a', 'x', slots: ['16:00–20:00']), _now),
        Availability.running,
      );
    });

    test('con dos franjas, vale si queda alguna', () {
      expect(
        availabilityOf(
          _event('a', 'x', slots: ['10:00–14:00', '18:00–21:00']),
          _now,
        ),
        Availability.upcoming,
      );
    });

    test('solo hora de inicio: se supone que dura dos horas', () {
      expect(
        availabilityOf(_event('a', 'x', slots: ['15:30']), _now),
        Availability.running,
      );
      expect(
        availabilityOf(_event('a', 'x', slots: ['14:30']), _now),
        Availability.finished,
      );
    });

    test('sin horario conocido: disponible todo el día', () {
      expect(availabilityOf(_event('a', 'x'), _now), Availability.allDay);
    });
  });

  group('Una sugerencia por categoría', () {
    test('elige una actividad de cada tipo, en el orden de las categorías', () {
      final events = [
        _event(
          'o',
          'Obra',
          category: CulturalCategory.teatro,
          slots: ['19:00'],
        ),
        _event(
          'm',
          'Concierto',
          category: CulturalCategory.musica,
          slots: ['20:00'],
        ),
        _event(
          'e',
          'Expo',
          category: CulturalCategory.exposiciones,
          slots: ['10:00–21:00'],
        ),
        _event(
          'g',
          'Tapas',
          category: CulturalCategory.gastronomia,
          slots: ['19:30'],
        ),
        _event(
          'c',
          'Película',
          category: CulturalCategory.cine,
          slots: ['21:00'],
        ),
        _event(
          't',
          'Taller',
          category: CulturalCategory.charlas,
          slots: ['18:00'],
        ),
        _event(
          'v',
          'Fiesta',
          category: CulturalCategory.eventos,
          slots: ['22:00'],
        ),
      ];
      final result = pickDaySuggestions(events, now: _now);
      expect(result.map((s) => s.event.category), suggestionCategories);
      expect(result.map((s) => s.event.id), [
        'm',
        'o',
        'e',
        'g',
        'c',
        't',
        'v',
      ]);
    });

    test('solo una por categoría aunque haya muchas', () {
      final events = [
        for (var i = 0; i < 5; i++)
          _event('m$i', 'Concierto $i', slots: ['19:00']),
        _event(
          'o',
          'Obra',
          category: CulturalCategory.teatro,
          slots: ['19:00'],
        ),
      ];
      final result = pickDaySuggestions(events, now: _now);
      expect(result, hasLength(2));
      expect(result.map((s) => s.event.category).toSet(), hasLength(2));
    });

    test('las categorías sin actividades disponibles se omiten', () {
      final events = [
        _event('m', 'Concierto', slots: ['20:00']),
        _event(
          'f',
          'Ya acabó',
          category: CulturalCategory.teatro,
          slots: ['10:00–12:00'],
        ),
        _event(
          't',
          'Mañana',
          category: CulturalCategory.cine,
          date: '2026-10-08',
          slots: ['20:00'],
        ),
      ];
      expect(pickDaySuggestions(events, now: _now).map((s) => s.event.id), [
        'm',
      ]);
    });

    test(
      'en una categoría prefiere la de pocos días a la exposición larga',
      () {
        final long = _event(
          'l',
          'Gran exposición',
          category: CulturalCategory.exposiciones,
          slots: ['10:00–21:00'],
          runStart: '2026-06-01',
          runEnd: '2027-01-01',
        );
        final short = _event(
          's',
          'Muestra breve',
          category: CulturalCategory.exposiciones,
          slots: ['19:00'],
          runStart: '2026-10-05',
          runEnd: '2026-10-09',
        );
        final result = pickDaySuggestions([long, short], now: _now);
        expect(result.single.event.id, 's');
        expect(result.single.reason, 'Empieza a las 19:00');
      },
    );

    test('a igualdad, prefiere la que empieza antes', () {
      final late = _event('l', 'Tarde', slots: ['22:00']);
      final soon = _event('s', 'Pronto', slots: ['18:00']);
      expect(pickDaySuggestions([late, soon], now: _now).single.event.id, 's');
    });

    test('explica por qué: en marcha, empieza a las..., solo unos días', () {
      final running = pickDaySuggestions([
        _event('a', 'A', slots: ['16:00–20:00']),
      ], now: _now);
      expect(running.single.reason, 'Está en marcha ahora mismo');
      final upcoming = pickDaySuggestions([
        _event('a', 'A', slots: ['19:30']),
      ], now: _now);
      expect(upcoming.single.reason, 'Empieza a las 19:30');
      final allDay = pickDaySuggestions([
        _event('a', 'A', runStart: '2026-10-06', runEnd: '2026-10-08'),
      ], now: _now);
      expect(allDay.single.reason, 'Solo se celebra unos días');
      final noInfo = pickDaySuggestions([
        _event('a', 'A', runStart: '2026-06-01', runEnd: '2027-01-01'),
      ], now: _now);
      expect(noInfo.single.reason, 'Disponible hoy');
    });

    test('sin actividades devuelve una lista vacía', () {
      expect(pickDaySuggestions(const [], now: _now), isEmpty);
    });
  });

  group('Pantalla', () {
    Widget screen(List<CulturalEvent> events) => MaterialApp(
      home: SuggestionOfDayScreen(repository: _Repo(events), clock: () => _now),
    );

    testWidgets('muestra una actividad por categoría', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(400, 4000));
      await tester.pumpWidget(
        screen([
          _event('m', 'Concierto en la plaza', slots: ['19:00']),
          _event(
            'o',
            'Obra de teatro',
            category: CulturalCategory.teatro,
            slots: ['20:00'],
          ),
          _event(
            'e',
            'Exposición de fotos',
            category: CulturalCategory.exposiciones,
            slots: ['19:00'],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hoy te recomendamos esto'), findsOneWidget);
      expect(find.text('Concierto en la plaza'), findsOneWidget);
      expect(find.text('Obra de teatro'), findsOneWidget);
      expect(find.text('Exposición de fotos'), findsOneWidget);
      // Sin nada relacionado con el tiempo atmosférico.
      expect(find.textContaining('tiempo'), findsNothing);
      expect(find.textContaining('lluvia'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('si hoy ya no queda nada lo dice', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        screen([
          _event('f', 'Ya acabó', slots: ['10:00–12:00']),
        ]),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hoy ya no quedan actividades'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'El botón de la sugerencia en la pantalla principal abre la pantalla',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(const ZaragozaCulturaApp(repository: _Repo([])));
      await tester.pumpAndSettle();

      expect(
        find.text('Hoy te recomendamos esto'),
        findsOneWidget,
      ); // subtítulo del botón
      await tester.tap(find.text('Sugerencia del día'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hoy ya no quedan actividades'),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    },
  );
}
