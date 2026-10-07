import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/notification_settings.dart';
import 'package:zaragoza_cultura_app/reminders.dart';
import 'package:zaragoza_cultura_app/useful_services.dart';
import 'package:zaragoza_cultura_app/weekend.dart';

// Miércoles 7 de octubre de 2026: el fin de semana es el 10 y el 11.
final _wednesday = DateTime(2026, 10, 7, 12);
const _sat = '2026-10-10';
const _sun = '2026-10-11';

var _n = 0;
CulturalEvent _event(
  String title,
  CulturalCategory category,
  String date, {
  String time = '',
  String runStart = '',
  String runEnd = '',
}) => CulturalEvent(
  id: 'id${_n++}',
  title: title,
  description: '',
  category: category,
  date: date,
  time: time,
  place: 'Sala',
  officialUrl: 'https://www.zaragoza.es',
  timeSlots: time.isEmpty ? const [] : [time],
  runStart: runStart,
  runEnd: runEnd,
);

class _Events extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _Events(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

class _NoMonuments extends MonumentsRepository {
  const _NoMonuments();

  @override
  Future<List<Monument>> loadCached() async => const [];

  @override
  Future<List<Monument>?> fetchFresh() async => const [];
}

class _NoServices extends ServicesRepository {
  const _NoServices();

  @override
  Future<List<ServiceGroup>> loadCached() async => const [];

  @override
  Future<List<ServiceGroup>?> fetchFresh() async => null;
}

class _NoWeather extends WeatherRepository {
  const _NoWeather();

  @override
  Future<int?> currentTemperature() async => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Qué fin de semana', () {
    test('entre semana, el sábado y el domingo que vienen', () {
      expect(weekendDays(_wednesday), [
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 11),
      ]);
      expect(
        weekendDays(DateTime(2026, 10, 9, 23)).first,
        DateTime(2026, 10, 10),
      );
      expect(weekendLabel(_wednesday), 'Sábado 10 y domingo 11 de octubre');
    });

    test('el sábado, hoy y mañana; el domingo, solo hoy', () {
      expect(weekendDays(DateTime(2026, 10, 10, 9)), [
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 11),
      ]);
      expect(weekendDays(DateTime(2026, 10, 11, 9)), [DateTime(2026, 10, 11)]);
      expect(weekendLabel(DateTime(2026, 10, 11, 9)), 'Domingo 11 de octubre');
    });

    test('cuando cae entre dos meses', () {
      expect(
        weekendLabel(DateTime(2026, 10, 29)),
        'Sábado 31 de octubre y domingo 1 de noviembre',
      );
    });
  });

  group('Selección', () {
    final events = [
      _event('Concierto A', CulturalCategory.musica, _sat, time: '20:00'),
      _event('Concierto B', CulturalCategory.musica, _sat, time: '22:00'),
      _event('Concierto C', CulturalCategory.musica, _sun, time: '12:00'),
      _event('Concierto D', CulturalCategory.musica, _sun, time: '19:00'),
      _event('Obra', CulturalCategory.teatro, _sat, time: '19:00'),
      _event('Obra', CulturalCategory.teatro, _sun, time: '19:00'),
      _event('Película del lunes', CulturalCategory.cine, '2026-10-12'),
      _event('Película', CulturalCategory.cine, _sun),
    ];

    test('hasta tres por tipo, solo del fin de semana y sin repetir', () {
      final groups = pickWeekendSuggestions(events, now: _wednesday);
      final byCategory = {
        for (final g in groups) g.category: [for (final e in g.events) e.title],
      };
      expect(byCategory[CulturalCategory.musica], [
        'Concierto A',
        'Concierto B',
        'Concierto C',
      ]);
      // La misma obra los dos días cuenta una vez.
      expect(byCategory[CulturalCategory.teatro], ['Obra']);
      expect(byCategory[CulturalCategory.cine], ['Película']);
      // Los tipos sin actividades no aparecen.
      expect(byCategory.containsKey(CulturalCategory.charlas), isFalse);
    });

    test('los tipos salen en el orden de «Mis preferencias»', () {
      final groups = pickWeekendSuggestions(
        events,
        now: _wednesday,
        preferred: const [CulturalCategory.cine, CulturalCategory.teatro],
      );
      expect(
        [for (final g in groups) g.category],
        [
          CulturalCategory.cine,
          CulturalCategory.teatro,
          CulturalCategory.musica,
        ],
      );
    });

    test('lo que dura pocos días va antes que las exposiciones largas', () {
      final groups = pickWeekendSuggestions([
        _event(
          'Expo de meses',
          CulturalCategory.exposiciones,
          _sat,
          runStart: '2026-09-01',
          runEnd: '2026-12-31',
        ),
        _event('Expo de fin de semana', CulturalCategory.exposiciones, _sun),
      ], now: _wednesday);
      expect(
        [for (final e in groups.single.events) e.title],
        ['Expo de fin de semana', 'Expo de meses'],
      );
    });

    test('ya en sábado, lo que ha terminado no se sugiere', () {
      final groups = pickWeekendSuggestions([
        _event('Matinal', CulturalCategory.musica, _sat, time: '10:00'),
        _event('Noche', CulturalCategory.musica, _sat, time: '22:00'),
      ], now: DateTime(2026, 10, 10, 18));
      expect([for (final e in groups.single.events) e.title], ['Noche']);
    });
  });

  group('Pantalla', () {
    final events = [
      _event('Concierto A', CulturalCategory.musica, _sat, time: '20:00'),
      _event('Película', CulturalCategory.cine, _sun),
    ];

    testWidgets('muestra el fin de semana y sus actividades por tipo', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'preferred_categories': ['cine'],
      });
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      await tester.pumpWidget(
        MaterialApp(
          home: WeekendScreen(
            repository: _Events(events),
            clock: () => _wednesday,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sugerencias fin de semana'), findsOneWidget);
      expect(find.text('Sábado 10 y domingo 11 de octubre'), findsOneWidget);
      expect(find.text('Ordenadas según tus preferencias.'), findsOneWidget);
      // Cine (preferido) va antes que Música.
      expect(
        tester.getTopLeft(find.text('Película')).dy,
        lessThan(tester.getTopLeft(find.text('Concierto A')).dy),
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('sin actividades lo explica', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WeekendScreen(
            repository: _Events([
              _event('Otro día', CulturalCategory.musica, '2026-10-13'),
            ]),
            clock: () => _wednesday,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Todavía no hay actividades publicadas'),
        findsOneWidget,
      );
      expect(find.textContaining('Mis preferencias'), findsOneWidget);
    });

    testWidgets('la portada tiene el botón entre Agenda y Monumentos', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: _Events(events),
            monumentsRepository: const _NoMonuments(),
            servicesRepository: const _NoServices(),
            weatherRepository: const _NoWeather(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double x(String label) => tester.getCenter(find.text(label)).dx;
      expect(x('Agenda'), lessThan(x('Fin de semana')));
      expect(x('Fin de semana'), lessThan(x('Monumentos')));
      expect(
        find.bySemanticsLabel('Sugerencias fin de semana'),
        findsOneWidget,
      );

      await tester.tap(find.text('Fin de semana'));
      await tester.pumpAndSettle();
      expect(find.byType(WeekendScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Aviso de los jueves', () {
    test('el próximo jueves a las 17:00', () {
      expect(nextWeekendReminder(_wednesday), DateTime(2026, 10, 8, 17));
      // Jueves antes de la hora: hoy mismo.
      expect(
        nextWeekendReminder(DateTime(2026, 10, 8, 9)),
        DateTime(2026, 10, 8, 17),
      );
      // Jueves ya pasada la hora: el de la semana siguiente.
      expect(
        nextWeekendReminder(DateTime(2026, 10, 8, 17)),
        DateTime(2026, 10, 15, 17),
      );
      expect(
        nextWeekendReminder(DateTime(2026, 10, 11)).weekday,
        DateTime.thursday,
      );
    });

    test('desactivado por defecto', () async {
      expect(await loadWeekendReminderEnabled(), isFalse);
    });

    testWidgets('Notificaciones reúne los dos avisos', (tester) async {
      final changes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            remindersEnabled: true,
            onRemindersChanged: (v) async {
              changes.add('favoritos=$v');
              return true;
            },
            onWeekendChanged: (v) async {
              changes.add('finde=$v');
              return true;
            },
            loadWeekendEnabled: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      SwitchListTile tile(String title) => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, title),
      );
      expect(tile('Avisos de mis favoritos').value, isTrue);
      expect(tile('Sugerencias para el fin de semana').value, isFalse);

      await tester.tap(find.text('Sugerencias para el fin de semana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avisos de mis favoritos'));
      await tester.pumpAndSettle();
      expect(changes, ['finde=true', 'favoritos=false']);
      expect(tile('Sugerencias para el fin de semana').value, isTrue);
      expect(tile('Avisos de mis favoritos').value, isFalse);
    });

    testWidgets('sin permiso de notificaciones el interruptor no cambia', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationSettingsScreen(
            remindersEnabled: false,
            onRemindersChanged: (_) async => true,
            onWeekendChanged: (_) async => false,
            loadWeekendEnabled: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sugerencias para el fin de semana'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Sugerencias para el fin de semana',
              ),
            )
            .value,
        isFalse,
      );
      expect(find.textContaining('permite las notificaciones'), findsOneWidget);
    });
  });
}
