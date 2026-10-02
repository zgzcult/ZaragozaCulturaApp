import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/useful_services.dart';

const _json = {
  'updated': '2026-10-02T08:00:00+00:00',
  'groups': [
    {
      'id': 'farmacias-guardia',
      'title': 'Farmacias de guardia',
      'items': [
        {
          'id': 'farmacias-guardia-8860',
          'name': 'Farmacia Artal Lerín, Ana Cristina',
          'address': 'Pº. de Sagasta, 8',
          'phone': '976226203',
          'call': '976226203',
          'info': 'De guardia: Abiertas de 9:15 h. a 9:15 h. del día siguiente',
          'url': '',
        },
      ],
    },
    {
      'id': 'hospitales',
      'title': 'Hospitales',
      'items': [
        {
          'id': 'hospitales-1',
          'name': 'Hospital Miguel Servet',
          'address': 'Paseo Isabel la Católica, 1-3',
          'phone': '976 765 500',
          'call': '976765500',
          'url': 'https://www.zaragoza.es/sede/servicio/equipamiento/1',
        },
        {'id': 'hospitales-2', 'name': 'Clínica Actur', 'phone': ''},
      ],
    },
    {
      'id': 'policia-nacional',
      'title': 'Policía Nacional',
      'items': [],
      'error': true,
    },
  ],
};

class _Repo extends ServicesRepository {
  final List<ServiceGroup>? fresh;

  const _Repo(this.fresh);

  @override
  Future<List<ServiceGroup>> loadCached() async => const [];

  @override
  Future<List<ServiceGroup>?> fetchFresh() async => fresh;
}

void main() {
  final groups = parseServices(_json);

  test('lee los grupos, sus lugares y los que fallaron', () {
    expect(
      [for (final g in groups) g.id],
      ['farmacias-guardia', 'hospitales', 'policia-nacional'],
    );
    expect(groups[1].items, hasLength(2));
    expect(groups[2].failed, isTrue);
    expect(parseServices('basura'), isEmpty);
  });

  test('cómo llegar busca por nombre y dirección, no por coordenadas', () {
    final link = serviceDirectionsLink(groups[1].items.first);
    expect(
      link.queryParameters['destination'],
      'Hospital Miguel Servet, Paseo Isabel la Católica, 1-3, Zaragoza',
    );
    expect(allPharmaciesLink.queryParameters['query'], 'farmacias cerca de mí');
  });

  test('busca sin tildes por nombre o calle', () {
    final items = groups[1].items;
    expect(searchServices(items, 'isabel catolica'), hasLength(1));
    expect(searchServices(items, 'clinica'), hasLength(1));
    expect(searchServices(items, ''), hasLength(2));
  });

  group('Pantallas', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('emergencias, grupos y farmacias de guardia', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        MaterialApp(home: UsefulServicesScreen(repository: _Repo(groups))),
      );
      await tester.pumpAndSettle();
      for (final text in ['112', '092', '091']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('1 abiertas hoy'), findsOneWidget);
      expect(find.text('Todas las farmacias'), findsOneWidget);
      expect(find.text('No disponible ahora mismo'), findsOneWidget);

      await tester.tap(find.text('Farmacias de guardia'));
      await tester.pumpAndSettle();
      expect(find.textContaining('De guardia: Abiertas'), findsOneWidget);
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.text('Cómo llegar'), findsOneWidget);
      // Sin mapa: solo lista.
      expect(find.byType(Image), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('un lugar sin teléfono ni dirección no ofrece esos botones', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ServiceCard(item: groups[1].items[1])),
        ),
      );
      expect(find.text('Llamar'), findsNothing);
      expect(find.text('Cómo llegar'), findsNothing);
    });

    testWidgets('sin conexión ni datos guardados ofrece reintentar', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: UsefulServicesScreen(repository: _Repo(null))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('la pantalla principal lleva a Servicios útiles', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(servicesRepository: _Repo(groups))),
      );
      await tester.scrollUntilVisible(find.text('Servicios útiles'), 100);
      await tester.tap(find.text('Servicios útiles'));
      await tester.pumpAndSettle();
      expect(find.text('Hospitales'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
