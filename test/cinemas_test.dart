import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/cinemas.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/useful_services.dart';

class _Events extends ZaragozaEventsRepository {
  const _Events();

  @override
  Future<List<CulturalEvent>> loadCached() async => const [];

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => null;
}

class _NoMonuments extends MonumentsRepository {
  const _NoMonuments();

  @override
  Future<List<Monument>> loadCached() async => const [];

  @override
  Future<List<Monument>?> fetchFresh() async => null;
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

Widget _home() => const MaterialApp(
  home: HomeScreen(
    repository: _Events(),
    monumentsRepository: _NoMonuments(),
    servicesRepository: _NoServices(),
    weatherRepository: _NoWeather(),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cada cine tiene nombre, dirección en Zaragoza y enlace seguro', () {
    expect(zaragozaCinemas.length, greaterThanOrEqualTo(6));
    for (final cinema in zaragozaCinemas) {
      expect(cinema.name, isNotEmpty);
      expect(cinema.address, contains('Zaragoza'), reason: cinema.name);
      expect(Uri.parse(cinema.url).scheme, 'https', reason: cinema.name);
    }
    expect(
      zaragozaCinemas.map((c) => c.name).toSet(),
      hasLength(zaragozaCinemas.length),
    );
    final link = cinemaDirectionsLink(zaragozaCinemas.first);
    expect(
      link.queryParameters['destination'],
      'Cines Palafox, Paseo de la Independencia, 12, 50004 Zaragoza',
    );
  });

  testWidgets('la pantalla lista los cines con sus dos botones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(const MaterialApp(home: CinemasScreen()));
    expect(find.text('Cine'), findsOneWidget);
    for (final cinema in zaragozaCinemas) {
      expect(find.text(cinema.name), findsOneWidget, reason: cinema.name);
    }
    expect(find.text('Ver cartelera'), findsNWidgets(zaragozaCinemas.length));
    expect(find.text('Cómo llegar'), findsNWidgets(zaragozaCinemas.length));
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'los accesos van en dos filas, con Cine junto a Rutas en la segunda',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(_home());
      await tester.pumpAndSettle();
      Offset at(String label) => tester.getCenter(find.text(label));
      final first = ['Agenda', 'Sugerencias fin de semana', 'Monumentos'];
      final second = ['Rutas', 'Cine'];
      for (final row in [first, second]) {
        for (var i = 1; i < row.length; i++) {
          expect(at(row[i - 1]).dx, lessThan(at(row[i]).dx));
          expect((at(row[0]).dy - at(row[i]).dy).abs(), lessThan(12));
        }
      }
      expect(at(first[0]).dy, lessThan(at(second[0]).dy));

      await tester.tap(find.text('Cine'));
      await tester.pumpAndSettle();
      expect(find.byType(CinemasScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('sin monumentos cargados no salen rutas «con 0 paradas»', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(_home());
    await tester.pumpAndSettle();
    expect(find.text('Rutas culturales'), findsNothing);
    expect(find.textContaining('0 PARADAS'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
}
