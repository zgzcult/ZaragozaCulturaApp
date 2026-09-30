import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/nearby.dart';

String _key(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

CulturalEvent _event(
  String id,
  String title, {
  double? lat,
  double? lng,
  int daysFromNow = 0,
  String place = 'Sala',
}) {
  return CulturalEvent(
    id: id,
    title: title,
    description: '',
    category: CulturalCategory.musica,
    date: _key(DateTime.now().add(Duration(days: daysFromNow))),
    time: '20:00',
    place: place,
    officialUrl: 'https://www.zaragoza.es',
    timeSlots: const ['20:00'],
    lat: lat,
    lng: lng,
  );
}

class _FakeLocation extends LocationService {
  final LocationResult result;

  /// Si es `false`, solo responde cuando se pide permiso explícitamente.
  final bool alreadyGranted;
  final List<bool> requests = [];

  _FakeLocation(this.result, {this.alreadyGranted = true});

  @override
  Future<LocationResult> locate({required bool askPermission}) async {
    requests.add(askPermission);
    if (!alreadyGranted && !askPermission) {
      return const LocationResult(LocationStatus.denied);
    }
    return result;
  }

  @override
  Future<void> openSettings() async {}
}

const _pilar = LocationResult(
  LocationStatus.ok,
  lat: zaragozaCenterLat,
  lng: zaragozaCenterLng,
);

Widget _screen(LocationService service, List<CulturalEvent> events) {
  return MaterialApp(
    home: Scaffold(
      body: NearbyScreen(
        events: events,
        locationService: service,
        enableTiles: false,
        cardBuilder: (e) => ListTile(title: Text(e.title)),
        dayLabel: (d) => 'Día $d',
        timeLabel: (e) => '',
        onOpen: (_) {},
      ),
    ),
  );
}

void main() {
  group('Distancias', () {
    test('calcula metros entre dos puntos', () {
      final meters = distanceMeters(
        zaragozaCenterLat,
        zaragozaCenterLng,
        41.6570,
        -0.8780,
      );
      expect(meters, inInclusiveRange(80, 120));
      expect(distanceMeters(41.65, -0.88, 41.65, -0.88), 0);
    });

    test('formatea metros y kilómetros', () {
      expect(formatDistance(4), '10 m');
      expect(formatDistance(349), '350 m');
      expect(formatDistance(1234), '1,2 km');
      expect(formatDistance(10500), '10,5 km');
    });
  });

  group('nearbyActivities', () {
    const from = '2026-10-05';
    const to = '2026-10-11';

    CulturalEvent at(
      String id,
      String title,
      String date, {
      double? lat = 41.6570,
      double? lng = -0.8780,
      String place = 'Sala',
    }) {
      return CulturalEvent(
        id: id,
        title: title,
        description: '',
        category: CulturalCategory.musica,
        date: date,
        time: '20:00',
        place: place,
        officialUrl: 'https://www.zaragoza.es',
        lat: lat,
        lng: lng,
      );
    }

    List<NearbyActivity> run(
      List<CulturalEvent> events, {
      double radius = 3000,
    }) => nearbyActivities(
      events,
      lat: zaragozaCenterLat,
      lng: zaragozaCenterLng,
      radiusMeters: radius,
      fromDate: from,
      toDate: to,
    );

    test(
      'una actividad con varias fechas sale una vez, con la más próxima',
      () {
        final results = run([
          at('3', 'Jazz', '2026-10-10'),
          at('1', 'Jazz', '2026-10-06'),
          at('2', 'Jazz', '2026-10-08'),
        ]);
        expect(results, hasLength(1));
        expect(results.single.event.date, '2026-10-06');
      },
    );

    test('respeta el periodo y el radio', () {
      final results = run([
        at('1', 'Dentro', '2026-10-06'),
        at('2', 'Fecha pasada', '2026-10-04'),
        at('3', 'Fecha lejana', '2026-10-12'),
        at('4', 'Muy lejos', '2026-10-06', lat: 41.75, lng: -0.80),
      ]);
      expect(results.map((r) => r.event.title), ['Dentro']);
    });

    test('ignora actividades sin coordenadas', () {
      expect(
        run([at('1', 'Sin sitio', '2026-10-06', lat: null, lng: null)]),
        isEmpty,
      );
    });

    test('ordena de la más cercana a la más lejana', () {
      final results = run([
        at('1', 'Lejos', '2026-10-06', lat: 41.675, lng: -0.865, place: 'A'),
        at('2', 'Cerca', '2026-10-06', lat: 41.6566, lng: -0.8775, place: 'B'),
        at('3', 'Medio', '2026-10-06', lat: 41.665, lng: -0.87, place: 'C'),
      ]);
      expect(results.map((r) => r.event.title), ['Cerca', 'Medio', 'Lejos']);
    });
  });

  group('Pantalla Cerca de mí', () {
    final near = _event('n', 'Concierto cercano', lat: 41.6570, lng: -0.8780);
    final far = _event(
      'f',
      'Concierto lejano',
      lat: 41.70,
      lng: -0.80,
      place: 'Otro',
    );

    testWidgets('con ubicación muestra lo cercano y el radio lo amplía', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(_screen(_FakeLocation(_pilar), [near, far]));
      await tester.pumpAndSettle();

      expect(find.textContaining('a menos de 3 km de ti'), findsOneWidget);
      expect(find.text('Concierto cercano'), findsOneWidget);
      expect(find.text('Concierto lejano'), findsNothing);

      await tester.tap(find.text('10 km'));
      await tester.pumpAndSettle();
      expect(find.text('Concierto lejano'), findsOneWidget);
      expect(find.textContaining('2 actividades'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets(
      'sin permiso previo explica el uso y pide la ubicación al pulsar',
      (tester) async {
        final service = _FakeLocation(_pilar, alreadyGranted: false);
        await tester.binding.setSurfaceSize(const Size(400, 1400));
        await tester.pumpWidget(_screen(service, [near]));
        await tester.pumpAndSettle();

        expect(find.textContaining('No se guarda ni se envía'), findsOneWidget);
        expect(service.requests, [false]); // al entrar no se pide permiso

        await tester.tap(find.text('Usar mi ubicación'));
        await tester.pumpAndSettle();
        expect(service.requests, [false, true]);
        expect(find.text('Concierto cercano'), findsOneWidget);

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets('si se deniega el permiso se puede ver desde el centro', (
      tester,
    ) async {
      final service = _FakeLocation(
        const LocationResult(LocationStatus.deniedForever),
        alreadyGranted: false,
      );
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(_screen(service, [near]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Usar mi ubicación'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir ajustes'), findsOneWidget);

      await tester.tap(find.text('Ver desde el centro de Zaragoza'));
      await tester.pumpAndSettle();
      expect(find.textContaining('de la Plaza del Pilar'), findsOneWidget);
      expect(find.text('Concierto cercano'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('La barra inferior tiene Cerca de mí entre Agenda y Buscar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeLocation(_pilar, alreadyGranted: false);
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    await tester.pumpWidget(
      ZaragozaCulturaApp(
        repository: _FakeRepo([
          _event('n', 'Concierto cercano', lat: 41.657, lng: -0.878),
        ]),
        locationService: service,
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Agenda',
      'Cerca de mí',
      'Buscar',
      'Favoritos',
      'Ajustes',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    final agenda = tester.getTopLeft(find.text('Agenda')).dx;
    final cerca = tester.getTopLeft(find.text('Cerca de mí')).dx;
    final buscar = tester.getTopLeft(find.text('Buscar')).dx;
    expect(agenda, lessThan(cerca));
    expect(cerca, lessThan(buscar));

    await tester.tap(find.text('Cerca de mí').last);
    await tester.pumpAndSettle();
    expect(find.text('Usar mi ubicación'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });
}

class _FakeRepo extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _FakeRepo(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}
