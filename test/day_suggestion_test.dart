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
  String place = 'Sala',
  List<String> slots = const [],
  String date = _today,
  String runStart = '',
  String runEnd = '',
  CulturalCategory category = CulturalCategory.musica,
}) {
  return CulturalEvent(
    id: id,
    title: title,
    description: '',
    category: category,
    date: date,
    time: slots.isEmpty ? '' : slots.first.split('–').first,
    place: place,
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

class _Weather extends WeatherSource {
  final DayWeather? weather;

  const _Weather(this.weather);

  @override
  Future<DayWeather?> today() async => weather;
}

const sunny = DayWeather(favorable: true, summary: 'Soleado, 22 °C');
const rainy = DayWeather(favorable: false, summary: 'Lluvia, 11 °C');

void main() {
  group('Interior o aire libre', () {
    test('lo deduce del nombre del lugar', () {
      expect(
        settingOf(
          _event('a', 'x', place: 'Parque Grande José Antonio Labordeta'),
        ),
        Setting.outdoor,
      );
      expect(
        settingOf(_event('a', 'x', place: 'Plaza del Pilar')),
        Setting.outdoor,
      );
      expect(
        settingOf(_event('a', 'x', place: 'Teatro Principal')),
        Setting.indoor,
      );
      expect(
        settingOf(_event('a', 'x', place: 'Museo de Goya')),
        Setting.indoor,
      );
      expect(
        settingOf(
          _event('a', 'x', place: 'Auditorio de Zaragoza Princesa Leonor'),
        ),
        Setting.indoor,
      );
    });

    test('un recinto cubierto gana si el nombre incluye un parque', () {
      expect(
        settingOf(_event('a', 'x', place: 'Centro Cívico Parque Goya')),
        Setting.indoor,
      );
    });

    test('si no se sabe, es desconocido', () {
      expect(
        settingOf(_event('a', 'x', place: 'Varios lugares')),
        Setting.unknown,
      );
    });
  });

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
      ); // hasta las 17:30
      expect(
        availabilityOf(_event('a', 'x', slots: ['14:30']), _now),
        Availability.finished,
      ); // acabó a las 16:30
    });

    test('sin horario conocido: disponible todo el día', () {
      expect(availabilityOf(_event('a', 'x'), _now), Availability.allDay);
    });
  });

  group('Elección de la sugerencia', () {
    final outdoor = _event(
      'o',
      'Concierto en el parque',
      place: 'Parque Grande',
      slots: ['19:00'],
    );
    final indoor = _event(
      'i',
      'Obra de teatro',
      place: 'Teatro Principal',
      slots: ['19:00'],
      category: CulturalCategory.teatro,
    );

    test('con buen tiempo gana el aire libre', () {
      final result = pickDaySuggestions(
        [indoor, outdoor],
        now: _now,
        weather: sunny,
      );
      expect(result.first.event.id, 'o');
      expect(result.first.reason, 'Hace buen tiempo y es al aire libre');
    });

    test('con mal tiempo gana el interior', () {
      final result = pickDaySuggestions(
        [outdoor, indoor],
        now: _now,
        weather: rainy,
      );
      expect(result.first.event.id, 'i');
      expect(result.first.reason, 'Con este tiempo, un plan de interior');
    });

    test('sin tiempo disponible sigue eligiendo', () {
      final result = pickDaySuggestions([outdoor, indoor], now: _now);
      expect(result, hasLength(2));
      expect(result.first.reason, 'Empieza a las 19:00');
    });

    test('descarta lo que ya terminó y lo de otros días', () {
      final finished = _event('f', 'Ya acabó', slots: ['10:00–12:00']);
      final tomorrow = _event(
        't',
        'Mañana',
        date: '2026-10-08',
        slots: ['20:00'],
      );
      final result = pickDaySuggestions([
        finished,
        tomorrow,
        indoor,
      ], now: _now);
      expect(result.map((s) => s.event.id), ['i']);
    });

    test(
      'prefiere las actividades de pocos días a las exposiciones largas',
      () {
        final expo = _event(
          'e',
          'Gran exposición',
          place: 'Museo',
          slots: ['10:00–21:00'],
          runStart: '2026-06-01',
          runEnd: '2027-01-01',
          category: CulturalCategory.exposiciones,
        );
        final result = pickDaySuggestions([expo, indoor], now: _now);
        expect(result.first.event.id, 'i');
      },
    );

    test('evita repetir categoría si hay alternativas', () {
      final a = _event('a', 'Concierto A', slots: ['19:00']);
      final b = _event('b', 'Concierto B', slots: ['19:30']);
      final c = _event(
        'c',
        'Obra',
        slots: ['19:00'],
        category: CulturalCategory.teatro,
        place: 'Teatro Principal',
      );
      final result = pickDaySuggestions([a, b, c], now: _now, count: 2);
      expect(result.map((s) => s.event.category).toSet(), hasLength(2));
    });

    test('máximo tres sugerencias', () {
      final many = [
        for (var i = 0; i < 10; i++)
          _event('e$i', 'Actividad $i', slots: ['19:00']),
      ];
      expect(pickDaySuggestions(many, now: _now), hasLength(3));
    });

    test('sin actividades devuelve una lista vacía', () {
      expect(pickDaySuggestions(const [], now: _now), isEmpty);
    });
  });

  group('Pantalla', () {
    Widget screen(List<CulturalEvent> events, DayWeather? weather) =>
        MaterialApp(
          home: SuggestionOfDayScreen(
            repository: _Repo(events),
            weatherSource: _Weather(weather),
            clock: () => _now,
          ),
        );

    testWidgets('muestra la recomendación y el tiempo', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      await tester.pumpWidget(
        screen([
          _event(
            'o',
            'Concierto en el parque',
            place: 'Parque Grande',
            slots: ['19:00'],
          ),
          _event(
            'i',
            'Obra de teatro',
            place: 'Teatro Principal',
            slots: ['19:00'],
            category: CulturalCategory.teatro,
          ),
        ], sunny),
      );
      await tester.pumpAndSettle();

      expect(find.text('Te recomendamos'), findsOneWidget);
      expect(find.textContaining('Soleado, 22 °C'), findsOneWidget);
      expect(find.text('Hace buen tiempo y es al aire libre'), findsOneWidget);
      expect(find.text('Concierto en el parque'), findsOneWidget);
      expect(find.text('Otras ideas para hoy'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('funciona sin datos del tiempo', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      await tester.pumpWidget(
        screen([
          _event(
            'i',
            'Obra de teatro',
            place: 'Teatro Principal',
            slots: ['19:00'],
            category: CulturalCategory.teatro,
          ),
        ], null),
      );
      await tester.pumpAndSettle();

      expect(find.text('Te recomendamos'), findsOneWidget);
      expect(find.textContaining('Buen día para planes'), findsNothing);
      expect(find.text('Empieza a las 19:00'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('si hoy ya no queda nada lo dice', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        screen([
          _event('f', 'Ya acabó', slots: ['10:00–12:00']),
        ], sunny),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hoy ya no quedan actividades'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'El botón Sugerencia del día de la pantalla principal abre la pantalla',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        const ZaragozaCulturaApp(
          repository: _Repo([]),
          weatherSource: _Weather(null),
        ),
      );
      await tester.pumpAndSettle();
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
