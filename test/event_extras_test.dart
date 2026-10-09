import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/event_extras.dart';
import 'package:zaragoza_cultura_app/main.dart';

final _now = DateTime(2026, 10, 9, 10);

CulturalEvent _event(
  String date, {
  String id = '',
  String sourceId = '77',
  String place = 'Centro de Historias',
  double? lat,
  double? lng,
}) => CulturalEvent(
  id: id.isEmpty ? 'e-$sourceId-$date' : id,
  title: 'Paco Roca',
  description: 'Texto propio.',
  category: CulturalCategory.exposiciones,
  date: date,
  time: '10:00',
  place: place,
  address: 'Plaza San Agustín, 2',
  officialUrl: 'https://www.zaragoza.es/sede/servicio/cultura/evento/77',
  sourceId: sourceId,
  lat: lat,
  lng: lng,
);

class _Events extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _Events(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

class _Venues extends VenuesRepository {
  final Map<String, VenueInfo> cached;
  final Map<String, VenueInfo>? fresh;

  const _Venues({this.cached = const {}, this.fresh});

  @override
  Future<Map<String, VenueInfo>> loadCached() async => cached;

  @override
  Future<Map<String, VenueInfo>?> fetchFresh() async => fresh;
}

const _long =
    'Acceso por rampa adaptada. Es accesible y no ofrece ninguna dificultad '
    'para la movilidad. Aparcamiento accesible reservado. Espacio accesible '
    'reservado. Aseos adaptados. Se permiten perros guía. Ascensor adaptado.';

Widget _extras(
  CulturalEvent event, {
  List<CulturalEvent> all = const [],
  VenuesRepository venues = const _Venues(),
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: EventExtras(
        event: event,
        repository: _Events(all),
        venues: venues,
        clock: () => _now,
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Otras fechas', () {
    test('las demás sesiones del mismo acto, futuras y una por día', () {
      final event = _event('2026-10-10');
      final all = [
        _event('2026-10-08'), // ya pasó
        event,
        _event('2026-10-12', id: 'tarde'),
        _event('2026-10-12', id: 'noche'),
        _event('2026-10-11'),
        _event('2026-10-11', sourceId: '99'), // otro acto
      ];
      final sessions = otherSessions(event, all, _now);
      expect(sessions.map((e) => e.date), ['2026-10-11', '2026-10-12']);
      expect(sessions.last.id, 'tarde');
    });

    test('sin código de acto no se agrupa nada', () {
      final event = _event('2026-10-10', sourceId: '');
      final all = [event, _event('2026-10-11', sourceId: '')];
      expect(otherSessions(event, all, _now), isEmpty);
    });

    test('etiqueta corta del día', () {
      expect(shortDayLabel(DateTime(2026, 10, 17)), 'sáb 17 oct');
      expect(shortDayLabel(DateTime(2026, 12, 2)), 'mié 2 dic');
    });

    testWidgets('pastillas con los días y «+N más» si son muchos', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      final event = _event('2026-10-10');
      final all = [
        event,
        for (var day = 11; day <= 22; day++) _event('2026-10-$day'),
      ];
      await tester.pumpWidget(_extras(event, all: all));
      await tester.pumpAndSettle();
      expect(find.text('Otras fechas'), findsOneWidget);
      expect(find.text('dom 11 oct'), findsOneWidget);
      expect(find.text('dom 18 oct'), findsOneWidget);
      expect(find.text('lun 19 oct'), findsNothing);
      await tester.tap(find.text('+4 más'));
      await tester.pumpAndSettle();
      expect(find.text('jue 22 oct'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('un acto de un solo día no enseña el bloque', (tester) async {
      final event = _event('2026-10-10');
      await tester.pumpWidget(_extras(event, all: [event]));
      await tester.pumpAndSettle();
      expect(find.text('Otras fechas'), findsNothing);
      expect(find.text('Sobre el lugar'), findsOneWidget);
    });
  });

  group('Sobre el lugar', () {
    test('lee los datos del servidor y descarta lo que no entiende', () {
      final venues = parseVenues({
        'Centro de Historias': {'phone': ' 976 721 885 ', 'transport': '22'},
        'Roto': 'texto',
      });
      expect(venues.keys, ['Centro de Historias']);
      expect(venues['Centro de Historias']!.phone, '976 721 885');
      expect(venues['Centro de Historias']!.accessibility, '');
      expect(parseVenues([1, 2]), isEmpty);
    });

    test('cómo llegar: por coordenadas o por nombre y dirección', () {
      final located = _event('2026-10-10', lat: 41.65, lng: -0.87);
      expect(
        eventDirectionsLink(located).queryParameters['destination'],
        '41.65,-0.87',
      );
      expect(
        eventDirectionsLink(_event('2026-10-10'))
            .queryParameters['destination'],
        'Centro de Historias, Plaza San Agustín, 2, Zaragoza',
      );
    });

    testWidgets('teléfono, autobuses y accesibilidad con «Ver más»', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      const venues = _Venues(
        cached: {
          'Centro de Historias': VenueInfo(
            phone: '976 721 885',
            transport: '22, 35, 36',
            accessibility: _long,
          ),
        },
      );
      await tester.pumpWidget(_extras(_event('2026-10-10'), venues: venues));
      await tester.pumpAndSettle();
      expect(find.text('Centro de Historias'), findsOneWidget);
      expect(find.text('Plaza San Agustín, 2'), findsOneWidget);
      expect(find.text('976 721 885'), findsOneWidget);
      expect(find.text('22, 35, 36'), findsOneWidget);
      expect(find.text('Cómo llegar'), findsOneWidget);
      expect(tester.widget<Text>(find.text(_long)).maxLines, 3);
      await tester.tap(find.text('Ver más'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(_long)).maxLines, isNull);
      expect(find.text('Ver más'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('sin datos del lugar queda la dirección y cómo llegar', (
      tester,
    ) async {
      await tester.pumpWidget(_extras(_event('2026-10-10')));
      await tester.pumpAndSettle();
      expect(find.text('Sobre el lugar'), findsOneWidget);
      expect(find.text('Cómo llegar'), findsOneWidget);
      expect(find.text('Teléfono'), findsNothing);
      expect(find.text('Autobuses'), findsNothing);
      expect(find.text('Accesibilidad'), findsNothing);
    });

    testWidgets('si no hay nada guardado, pide los datos al servidor', (
      tester,
    ) async {
      const venues = _Venues(
        fresh: {'Centro de Historias': VenueInfo(transport: '22, 35, 36')},
      );
      await tester.pumpWidget(_extras(_event('2026-10-10'), venues: venues));
      await tester.pumpAndSettle();
      expect(find.text('22, 35, 36'), findsOneWidget);
    });

    testWidgets('sin lugar no hay bloque', (tester) async {
      await tester.pumpWidget(_extras(_event('2026-10-10', place: '')));
      await tester.pumpAndSettle();
      expect(find.text('Sobre el lugar'), findsNothing);
    });
  });

  testWidgets(
    'en la ficha van después de la descripción y antes de la fuente',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 3000));
      final event = _event('2026-10-10');
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: event,
            isFavorite: false,
            onToggleFavorite: () {},
            repository: _Events([event, _event('2026-10-11')]),
            venues: const _Venues(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final description = tester.getTopLeft(find.text('Descripción')).dy;
      final dates = tester.getTopLeft(find.text('Otras fechas')).dy;
      final venue = tester.getTopLeft(find.text('Sobre el lugar')).dy;
      final source = tester.getTopLeft(find.textContaining('Fuente:')).dy;
      expect(description, lessThan(dates));
      expect(dates, lessThan(venue));
      expect(venue, lessThan(source));
      await tester.binding.setSurfaceSize(null);
    },
  );
}
