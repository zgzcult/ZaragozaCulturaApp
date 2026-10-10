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
          'horario': 'Lunes a viernes de 9 a 21 h.',
          'url': '',
        },
      ],
    },
    {
      'id': 'bibliotecas',
      'title': 'Bibliotecas municipales',
      'items': [
        {
          'id': 'bibliotecas-916',
          'name': 'Biblioteca Benjamín Jarnés (Actur-Rey Fernando)',
          'address': 'Calle Pedro Laín Entralgo 15, 50018 Zaragoza',
          'phone': '976 726 108',
          'call': '976726108',
          'horario': '• Lunes: de 15 a 21 h.',
          'url': 'https://www.zaragoza.es/sede/servicio/equipamiento/916',
        },
        {'id': 'bibliotecas-2', 'name': 'Biblioteca Sin Datos', 'phone': ''},
      ],
    },
    {
      'id': 'centros-salud',
      'title': 'Centros Salud Públicos',
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
      ['farmacias-guardia', 'bibliotecas', 'centros-salud'],
    );
    expect(groups[1].items, hasLength(2));
    expect(groups[2].failed, isTrue);
    expect(parseServices('basura'), isEmpty);
  });

  test('cómo llegar busca por nombre y dirección, no por coordenadas', () {
    final link = serviceDirectionsLink(groups[1].items.first);
    expect(
      link.queryParameters['destination'],
      'Biblioteca Benjamín Jarnés (Actur-Rey Fernando), '
      'Calle Pedro Laín Entralgo 15, 50018 Zaragoza, Zaragoza',
    );
  });

  test('busca sin tildes por nombre o calle', () {
    final items = groups[1].items;
    expect(searchServices(items, 'lain entralgo'), hasLength(1));
    expect(searchServices(items, 'sin datos'), hasLength(1));
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
      // Ya no hay enlace a «todas las farmacias» ni a Google Maps.
      expect(find.text('Todas las farmacias'), findsNothing);
      expect(find.text('2 bibliotecas'), findsOneWidget);
      expect(find.text('No disponible ahora mismo'), findsOneWidget);

      await tester.tap(find.text('Farmacias de guardia'));
      await tester.pumpAndSettle();
      // Dos horarios distintos y bien rotulados: el de guardia y el habitual.
      expect(find.textContaining('De guardia: Abiertas'), findsOneWidget);
      expect(
        find.text('Horario habitual:\nLunes a viernes de 9 a 21 h.'),
        findsOneWidget,
      );
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.text('Cómo llegar'), findsOneWidget);
      // Sin mapa: solo lista.
      expect(find.byType(Image), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('en bibliotecas el horario no lleva el rótulo «habitual»', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        MaterialApp(home: ServiceGroupScreen(group: groups[1])),
      );
      expect(find.text('• Lunes: de 15 a 21 h.'), findsOneWidget);
      expect(find.textContaining('Horario habitual'), findsNothing);
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

    testWidgets('la portada ya no enseña el acceso a Servicios útiles', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(servicesRepository: _Repo(groups))),
      );
      await tester.pumpAndSettle();
      expect(showServicesShortcut, isFalse);
      expect(find.text('Servicios'), findsNothing);
      expect(find.text('Cine'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
