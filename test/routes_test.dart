import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/routes.dart';

const _foro = Monument(
  id: 'monumento-2',
  name: 'Museo del Foro de Caesaraugusta',
  lat: 41.655185,
  lng: -0.876352,
);
const _termas = Monument(
  id: 'monumento-4',
  name: 'Museo de las Termas Públicas de Caesaraugusta',
  lat: 41.65343,
  lng: -0.877213,
);
const _teatro = Monument(
  id: 'monumento-5',
  name: 'Museo del Teatro de Caesaraugusta',
  lat: 41.652607,
  lng: -0.877387,
);
const _sinUbicacion = Monument(id: 'monumento-3', name: 'Puerto Fluvial');

void main() {
  test('las rutas son las oficiales y citan su página de Turismo', () {
    expect(
      [for (final r in cityRoutes) r.id],
      ['caesaraugusta', 'mudejar', 'renacentista', 'goya', 'sitios'],
    );
    for (final route in cityRoutes) {
      expect(
        route.sourceUrl,
        startsWith('https://www.zaragoza.es/sede/portal/turismo/'),
        reason: route.id,
      );
      expect(route.intro.length, greaterThan(120), reason: route.id);
      expect(route.stops.length, greaterThanOrEqualTo(3), reason: route.id);
    }
  });

  test(
    'las paradas que faltan en el listado se omiten; las plazas se quedan',
    () {
      final roman = cityRoutes.first;
      final stops = resolveStops(roman, const [_foro, _termas]);
      expect(
        [for (final s in stops) s.name],
        [
          'Museo del Foro de Caesaraugusta',
          'Museo de las Termas Públicas de Caesaraugusta',
        ],
      );
      final sitios = cityRoutes.last;
      expect(
        resolveStops(sitios, const []).map((s) => s.name),
        contains('Plaza de España'),
      );
    },
  );

  test('distancia a pie aproximada y enlace a Google Maps con paradas', () {
    final stops = [
      const ResolvedStop(RouteStop.monument('monumento-2'), _foro),
      const ResolvedStop(RouteStop.monument('monumento-3'), _sinUbicacion),
      const ResolvedStop(RouteStop.monument('monumento-4'), _termas),
      const ResolvedStop(RouteStop.monument('monumento-5'), _teatro),
    ];
    final meters = walkingMeters(stops);
    // Unos 300 m en línea recta, más el 30 % por las calles.
    expect(meters, inInclusiveRange(350, 450));
    expect(walkingLabel(meters), '400 m · 5 min a pie');
    expect(walkingLabel(1840), '1,8 km · 25 min a pie');

    final link = routeMapsLink(stops)!;
    expect(link.queryParameters['origin'], '41.655185,-0.876352');
    expect(link.queryParameters['destination'], '41.652607,-0.877387');
    expect(link.queryParameters['waypoints'], '41.65343,-0.877213');
    expect(link.queryParameters['travelmode'], 'walking');
    expect(routeMapsLink(stops.sublist(0, 2)), isNull);
  });

  testWidgets('la ficha de una ruta muestra introducción, paradas y enlaces', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    await tester.pumpWidget(
      MaterialApp(
        home: RouteDetailScreen(
          route: cityRoutes.first,
          monuments: const [_foro, _termas, _teatro],
        ),
      ),
    );
    expect(find.text('Zaragoza romana'), findsOneWidget);
    expect(find.textContaining('14 a. C.'), findsOneWidget);
    expect(find.text('3 paradas'), findsOneWidget);
    expect(find.textContaining('más de 6.000 espectadores'), findsOneWidget);
    expect(find.text('Ver la ruta en Google Maps'), findsOneWidget);
    expect(find.text('Visita guiada oficial'), findsOneWidget);

    await tester.tap(find.text('Museo del Foro de Caesaraugusta'));
    await tester.pumpAndSettle();
    expect(find.byType(MonumentDetailScreen), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
