import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/nearby.dart';
import 'package:zaragoza_cultura_app/restaurants.dart';

class _FakePlaces extends PlacesRepository {
  final List<Place> cached;
  final List<Place>? fresh;

  const _FakePlaces({this.cached = const [], this.fresh});

  @override
  Future<List<Place>> loadCached() async => cached;

  @override
  Future<List<Place>?> fetchFresh() async => fresh;
}

class _NoLocation extends LocationService {
  const _NoLocation();

  @override
  Future<LocationResult> locate({required bool askPermission}) async =>
      const LocationResult(LocationStatus.denied);

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<LocationStatus> requestPermission() async => LocationStatus.denied;

  @override
  Future<void> openSettings() async {}
}

const _cachirulo = Place(
  id: 'r1',
  name: 'El Cachirulo',
  address: 'Ctra. de Logroño Km. 1,500, 50011',
  phone: '976 460 146',
  lat: 41.6563,
  lng: -0.8773,
);

Widget _screen(PlacesRepository repo) => MaterialApp(
  home: RestaurantsScreen(
    repository: repo,
    locationService: const _NoLocation(),
    enableTiles: false,
  ),
);

void main() {
  group('Datos', () {
    test('parsePlaces ignora los que no tienen nombre y conserva los que no tienen coordenadas', () {
      final places = parsePlaces([
        {'id': 'a', 'name': 'Casa Lac', 'lat': 41.65, 'lng': -0.88},
        {'id': 'b', 'name': '', 'lat': 41.65, 'lng': -0.88},
        {'id': 'c', 'name': 'Sin sitio'},
        'basura',
      ]);
      expect(places.map((p) => p.name), ['Casa Lac', 'Sin sitio']);
    });

    test('el enlace de Google Maps lleva nombre, dirección y Zaragoza', () {
      final uri = googleMapsLink(_cachirulo);
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search/');
      final query = uri.queryParameters['query']!;
      expect(query, contains('El Cachirulo'));
      expect(query, contains('Ctra. de Logroño'));
      expect(query, contains('Zaragoza'));
      expect(uri.queryParameters['api'], '1');
    });
  });

  group('Agrupación de marcadores', () {
    // Tres restaurantes muy juntos y uno lejano.
    const near = [
      Place(id: '1', name: 'A', lat: 41.6563, lng: -0.8773),
      Place(id: '2', name: 'B', lat: 41.6564, lng: -0.8774),
      Place(id: '3', name: 'C', lat: 41.6565, lng: -0.8772),
    ];
    const far = Place(id: '4', name: 'D', lat: 41.70, lng: -0.80);

    test('con poco zoom los cercanos se agrupan', () {
      final clusters = clusterPlaces([...near, far], zoom: 12);
      expect(clusters, hasLength(2));
      final group = clusters.firstWhere((c) => c.places.length > 1);
      expect(group.places, hasLength(3));
      expect(group.lat, closeTo(41.6564, 0.001));
      expect(group.isSingle, isFalse);
    });

    test('con mucho zoom cada uno queda aparte', () {
      final clusters = clusterPlaces([...near, far], zoom: 18);
      expect(clusters, hasLength(4));
      expect(clusters.every((c) => c.isSingle), isTrue);
    });

    test('nunca se pierde ni se duplica un lugar', () {
      for (final zoom in [10.0, 12.0, 14.0, 16.0, 18.0]) {
        final clusters = clusterPlaces([...near, far], zoom: zoom);
        final ids = clusters.expand((c) => c.places).map((p) => p.id).toList()
          ..sort();
        expect(ids, ['1', '2', '3', '4'], reason: 'zoom $zoom');
      }
    });

    test('sin lugares no hay grupos', () {
      expect(clusterPlaces(const [], zoom: 14), isEmpty);
    });
  });

  group('Lista con buscador', () {
    const casaLac = Place(
      id: 'r2',
      name: 'Casa Lac',
      address: 'Calle Mayor, 3, 50001',
    );
    const laManana = Place(
      id: 'r3',
      name: 'Bar La Mañana',
      address: 'Plaza Sas, 1, 50003',
    );
    const todos = _FakePlaces(fresh: [_cachirulo, casaLac, laManana]);

    Future<void> openList(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(_screen(todos));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
    }

    test('los lugares sin coordenadas no entran en la agrupación del mapa', () {
      final clusters = clusterPlaces(const [_cachirulo, casaLac], zoom: 14);
      final ids = clusters.expand((c) => c.places).map((p) => p.id).toList();
      expect(ids, ['r1']);
      expect(casaLac.hasLocation, isFalse);
      expect(_cachirulo.hasLocation, isTrue);
    });

    test('parsePlaces conserva los que no tienen coordenadas', () {
      final places = parsePlaces([
        {
          'id': 'a',
          'name': 'Casa Lac',
          'address': 'Calle Mayor, 3',
          'lat': null,
          'lng': null,
        },
      ]);
      expect(places, hasLength(1));
      expect(places.single.hasLocation, isFalse);
    });

    testWidgets('el mapa solo cuenta los que tienen ubicación', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(_screen(todos));
      await tester.pumpAndSettle();
      expect(find.text('1 restaurante en el mapa'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('la lista muestra todos, ordenados por nombre', (tester) async {
      await openList(tester);
      expect(find.text('3 restaurantes'), findsOneWidget);
      final a = tester.getTopLeft(find.text('Bar La Mañana')).dy;
      final b = tester.getTopLeft(find.text('Casa Lac')).dy;
      final c = tester.getTopLeft(find.text('El Cachirulo')).dy;
      expect(a, lessThan(b));
      expect(b, lessThan(c));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets(
      'el buscador filtra por nombre o calle, sin tildes ni mayúsculas',
      (tester) async {
        await openList(tester);

        await tester.enterText(find.byType(TextField), 'MAÑANA');
        await tester.pumpAndSettle();
        expect(find.text('Bar La Mañana'), findsOneWidget);
        expect(find.text('Casa Lac'), findsNothing);
        expect(find.text('1 de 3 restaurantes'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'mayor');
        await tester.pumpAndSettle();
        expect(find.text('Casa Lac'), findsOneWidget); // por la calle
        expect(find.text('Bar La Mañana'), findsNothing);

        await tester.enterText(find.byType(TextField), 'zzzz');
        await tester.pumpAndSettle();
        expect(
          find.text('Ningún restaurante coincide con tu búsqueda.'),
          findsOneWidget,
        );
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'uno sin ubicación abre su tarjeta con aviso y enlace a Google Maps',
      (tester) async {
        await openList(tester);
        await tester.tap(find.text('Casa Lac'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Calle Mayor, 3'), findsWidgets);
        expect(
          find.textContaining('No aparece en el mapa de la app'),
          findsOneWidget,
        );
        expect(find.text('Ver en Google Maps'), findsOneWidget);
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets('en la lista no aparece el botón de mi ubicación', (
      tester,
    ) async {
      await openList(tester);
      expect(find.byTooltip('Mi ubicación'), findsNothing);
      await tester.tap(find.text('Mapa'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mi ubicación'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Pantalla Restaurantes', () {
    testWidgets('muestra el total y abre la tarjeta al tocar un marcador', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(_screen(const _FakePlaces(fresh: [_cachirulo])));
      await tester.pumpAndSettle();

      expect(find.text('1 restaurante en el mapa'), findsOneWidget);

      // Un solo restaurante: el marcador es el icono de cubiertos.
      await tester.tap(find.byIcon(Icons.restaurant));
      await tester.pumpAndSettle();

      expect(find.text('El Cachirulo'), findsOneWidget);
      expect(find.textContaining('Ctra. de Logroño'), findsOneWidget);
      expect(find.text('976 460 146'), findsOneWidget);
      expect(find.text('Ver en Google Maps'), findsOneWidget);
      final title = tester.widget<Text>(find.text('El Cachirulo'));
      expect(title.style?.fontWeight, FontWeight.w800);
      // Sin estrellas ni "tenedores": solo el enlace a Google.
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.textContaining('tenedor'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('usa lo guardado si no hay conexión', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        _screen(const _FakePlaces(cached: [_cachirulo], fresh: null)),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 restaurante en el mapa'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('sin datos ni conexión ofrece reintentar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(_screen(const _FakePlaces()));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  testWidgets('El botón Restaurantes de la pantalla principal abre el mapa', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    await tester.pumpWidget(
      const ZaragozaCulturaApp(
        placesRepository: _FakePlaces(fresh: [_cachirulo]),
        locationService: _NoLocation(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Comer'));
    await tester.pumpAndSettle();

    expect(find.text('1 restaurante en el mapa'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
