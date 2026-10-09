import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/notifications_screen.dart';
import 'package:zaragoza_cultura_app/reminders.dart';
import 'package:zaragoza_cultura_app/useful_services.dart';

const _id = '0123456789abcdef0123456789abcdef01234567';
final _now = DateTime(2026, 10, 9, 19, 15);

CulturalEvent _event() => CulturalEvent(
  id: _id,
  title: 'Noche de jazz',
  description: 'Concierto.',
  category: CulturalCategory.musica,
  date: '2026-10-10',
  time: '20:30',
  place: 'Teatro Principal',
  officialUrl: 'https://www.zaragoza.es',
  timeSlots: const ['20:30'],
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

ReminderPlan _plan(
  DateTime when, {
  String id = _id,
  String title = 'Mañana: Noche de jazz',
}) => ReminderPlan(id: 1, eventId: id, when: when, title: title, body: '20:30');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReminderInbox.unread.value = 0;
  });

  group('Registro de avisos', () {
    test('un aviso programado pasa a «llegado» cuando llega su hora', () {
      final log = mergeReminderLog(const [], [
        _plan(DateTime(2026, 10, 9, 18)),
      ], now: DateTime(2026, 10, 9, 12));
      expect(deliveredReminders(log, now: DateTime(2026, 10, 9, 12)), isEmpty);
      expect(deliveredReminders(log, now: _now), hasLength(1));
    });

    test('un aviso leído desaparece al pasar el día de la actividad', () {
      // Aviso del jueves 8 a las 18:00 para una actividad del viernes 9.
      final leido = ReminderEntry(
        eventId: _id,
        when: DateTime(2026, 10, 8, 18),
        title: 'Mañana: Noche de jazz',
        body: '20:30',
        read: true,
      );
      final sinLeer = ReminderEntry(
        eventId: 'otro',
        when: DateTime(2026, 10, 8, 18),
        title: 'Mañana: Teatro',
        body: '',
      );
      List<String> ids(DateTime now) => [
        for (final e in deliveredReminders([leido, sinLeer], now: now))
          e.eventId,
      ];
      // El mismo día de la actividad sigue ahí aunque esté leído.
      expect(ids(DateTime(2026, 10, 9, 23, 59)), containsAll([_id, 'otro']));
      // Pasado ese día, el leído desaparece y el no leído se queda.
      expect(ids(DateTime(2026, 10, 10, 0, 1)), ['otro']);
      // También se limpia del registro guardado.
      final log = mergeReminderLog(
        [leido, sinLeer],
        const [],
        now: DateTime(2026, 10, 10, 9),
      );
      expect(log.map((e) => e.eventId), ['otro']);
    });

    test('el aviso del fin de semana dura hasta que acaba el domingo', () {
      final aviso = ReminderEntry(
        eventId: weekendPayload,
        when: DateTime(2026, 10, 8, 17), // jueves
        title: 'Sugerencias para el fin de semana',
        body: '',
        read: true,
      );
      expect(
        deliveredReminders([aviso], now: DateTime(2026, 10, 11, 22)),
        hasLength(1),
      );
      expect(
        deliveredReminders([aviso], now: DateTime(2026, 10, 12, 8)),
        isEmpty,
      );
    });

    test(
      'al reprogramar se conservan los llegados y se sustituyen los futuros',
      () {
        final llegado = ReminderEntry(
          eventId: 'a1',
          when: DateTime(2026, 10, 8, 18),
          title: 'Llegado',
          body: '',
          read: true,
        );
        final futuroViejo = ReminderEntry(
          eventId: 'b2',
          when: DateTime(2026, 10, 20, 18),
          title: 'Ya no es favorito',
          body: '',
        );
        final log = mergeReminderLog(
          [llegado, futuroViejo],
          [_plan(DateTime(2026, 10, 12, 18), id: 'c3', title: 'Nuevo')],
          now: _now,
        );
        expect([for (final e in log) e.title], ['Nuevo', 'Llegado']);
        expect(log.last.read, isTrue);
      },
    );

    test('los avisos de hace más de dos semanas se olvidan', () {
      final viejo = ReminderEntry(
        eventId: 'a1',
        when: _now.subtract(const Duration(days: 15)),
        title: 'Viejo',
        body: '',
      );
      expect(mergeReminderLog([viejo], const [], now: _now), isEmpty);
    });

    test('cuenta los no leídos y permite marcarlos', () async {
      await ReminderInbox.record([
        _plan(DateTime(2026, 10, 9, 18)),
        _plan(DateTime(2026, 10, 9, 18, 5), id: 'otro', title: 'Otro'),
      ], now: DateTime(2026, 10, 9, 12));
      expect(ReminderInbox.unread.value, 0); // aún no han llegado

      expect(await ReminderInbox.refresh(now: _now), 2);
      await ReminderInbox.markRead(eventId: _id, now: _now);
      expect(ReminderInbox.unread.value, 1);
      await ReminderInbox.markRead(now: _now);
      expect(ReminderInbox.unread.value, 0);
      // Siguen en el buzón, ya leídos.
      expect(await ReminderInbox.delivered(now: _now), hasLength(2));
    });

    test('etiqueta del día', () {
      expect(reminderDayLabel(DateTime(2026, 10, 9, 18), _now), 'Hoy');
      expect(reminderDayLabel(DateTime(2026, 10, 8, 18), _now), 'Ayer');
      expect(reminderDayLabel(DateTime(2026, 10, 5, 18), _now), '5 oct');
    });
  });

  group('Buzón', () {
    testWidgets('lista los avisos y al tocar uno abre su actividad', (
      tester,
    ) async {
      await ReminderInbox.record([
        _plan(DateTime(2026, 10, 9, 18)),
      ], now: DateTime(2026, 10, 9, 12));
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            repository: _Events([_event()]),
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mañana: Noche de jazz'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Marcar leídos'), findsOneWidget);

      await tester.tap(find.text('Mañana: Noche de jazz'));
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsOneWidget);
      expect(find.text('Noche de jazz'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      // Ya está leído: desaparece el botón.
      expect(find.text('Marcar leídos'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('sin avisos explica cuándo llegan', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NotificationsScreen(clock: () => _now)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No tienes avisos.'), findsOneWidget);
    });

    testWidgets('la campana de la portada muestra los avisos sin leer', (
      tester,
    ) async {
      await ReminderInbox.record([
        _plan(DateTime.now().subtract(const Duration(hours: 1))),
      ], now: DateTime.now().subtract(const Duration(hours: 3)));
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: _Events([_event()]),
            monumentsRepository: const _NoMonuments(),
            servicesRepository: const _NoServices(),
            weatherRepository: const _NoWeather(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Avisos: 1 sin leer'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // el número de la campana

      await tester.tap(find.byTooltip('Avisos: 1 sin leer'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Enlace a una actividad', () {
    test('reconoce los enlaces de actividad', () {
      expect(eventIdFromRoute('/evento/$_id'), _id);
      expect(eventIdFromRoute('/app/evento/$_id'), _id);
      expect(eventIdFromRoute('/evento/${_id.toUpperCase()}/'), _id);
      expect(eventIdFromRoute('/'), isNull);
      expect(eventIdFromRoute('/evento/'), isNull);
      expect(eventIdFromRoute('/evento/no-es-un-id'), isNull);
      expect(eventIdFromRoute(null), isNull);
    });

    testWidgets('abre la ficha de la actividad', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      await tester.pumpWidget(
        MaterialApp(
          home: EventLinkScreen(eventId: _id, repository: _Events([_event()])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('si la actividad ya no existe lo dice', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EventLinkScreen(eventId: _id, repository: _Events([])),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Esta actividad ya no está en la agenda.'),
        findsOneWidget,
      );
      expect(find.text('Ver la agenda'), findsOneWidget);
    });

    testWidgets('un enlace abre la actividad sobre la portada', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ZaragozaCulturaApp(repository: _Events([_event()]), navigatorKey: key),
      );
      await tester.pumpAndSettle();
      key.currentState!.pushNamed('/evento/$_id');
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsOneWidget);

      // Un enlace que no es de una actividad no añade ninguna pantalla.
      key.currentState!.pop();
      await tester.pumpAndSettle();
      key.currentState!.pushNamed('/inicio');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(key.currentState!.canPop(), isFalse);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
