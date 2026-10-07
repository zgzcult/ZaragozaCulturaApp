import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/routes.dart';

const _json = [
  {
    'id': 'monumento-2',
    'name': 'Museo del Foro de Caesaraugusta',
    'description': 'El Foro es el centro neurálgico de la ciudad romana.',
    'horario': 'Martes a sábado de 10 a 14h\nLunes cerrado',
    'price': 'Entrada: 3 euros',
    'datacion': 'Siglo I a.C. - Siglo I d.C.',
    'estilo': 'romano',
    'styles': ['Romano'],
    'museum': true,
    'top': true,
    'address': 'Plaza de la Seo, 2',
    'phone': '976 72 12 21 - Reservas 976 72 60 75',
    'url': 'https://www.zaragoza.es/sede/portal/turismo/servicio/monumento/2',
    'lat': 41.655183,
    'lng': -0.876353,
    'updated': '2018-06-05',
  },
  {
    'id': 'monumento-5',
    'name': 'Iglesia de San Pablo',
    'description': 'Templo mudéjar.',
    'datacion': 'Siglo XIV',
    'estilo': 'mudejar',
    'styles': ['Mudéjar'],
    'top': true,
    'address': 'Calle San Pablo, 42',
    'updated': '2023-02-10',
  },
  {
    'id': 'monumento-9',
    'name': 'Arboleda de Macanaz',
    'estilo': 'entorno',
    'styles': ['Naturaleza'],
    'address': 'Ribera del Ebro',
  },
  {'id': 'sin-nombre', 'name': '  '},
];

class _FakeRepository extends MonumentsRepository {
  final List<Monument>? fresh;

  const _FakeRepository(this.fresh);

  @override
  Future<List<Monument>> loadCached() async => const [];

  @override
  Future<List<Monument>?> fetchFresh() async => fresh;
}

void main() {
  final monuments = parseMonuments(_json);

  group('Datos', () {
    test('lee los monumentos y descarta los que no tienen nombre', () {
      expect(monuments, hasLength(3));
      final foro = monuments.first;
      expect(foro.museum, isTrue);
      expect(foro.top, isTrue);
      expect(foro.styles, ['Romano']);
      expect(foro.hasLocation, isTrue);
      expect(monuments[2].hasLocation, isFalse);
    });

    test('los filtros son los fijos más los estilos presentes, en orden', () {
      expect(monumentFilters(monuments), [
        'Todos',
        'Imprescindibles',
        'Museos',
        'Romano',
        'Mudéjar',
        'Naturaleza',
      ]);
    });

    test('filtra por tipo y estilo, y busca sin tildes', () {
      List<String> names(List<Monument> list) => [for (final m in list) m.name];
      expect(names(filterMonuments(monuments, filter: 'Museos')), [
        'Museo del Foro de Caesaraugusta',
      ]);
      expect(names(filterMonuments(monuments, filter: 'Mudéjar')), [
        'Iglesia de San Pablo',
      ]);
      expect(names(filterMonuments(monuments, query: 'mudejar')), [
        'Iglesia de San Pablo',
      ]);
      expect(names(filterMonuments(monuments, query: 'seo')), [
        'Museo del Foro de Caesaraugusta',
      ]);
      // Primero los imprescindibles, luego por orden alfabético.
      expect(names(filterMonuments(monuments)), [
        'Iglesia de San Pablo',
        'Museo del Foro de Caesaraugusta',
        'Arboleda de Macanaz',
      ]);
    });

    test('cómo llegar abre la ruta a pie de Google Maps', () {
      final link = directionsLink(monuments.first);
      expect(link.host, 'www.google.com');
      expect(link.queryParameters['destination'], '41.655183,-0.876353');
      expect(link.queryParameters['travelmode'], 'walking');
      expect(
        directionsLink(monuments[2]).queryParameters['destination'],
        contains('Arboleda de Macanaz'),
      );
    });

    test('toma el primer teléfono del texto', () {
      expect(
        firstPhoneNumber('976 72 12 21 - Reservas 976 72 60 75'),
        '976721221',
      );
      expect(firstPhoneNumber(''), isNull);
      expect(firstPhoneNumber('Sin teléfono'), isNull);
    });
  });

  group('Pantallas', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('lista con filtros y ficha con horario, precio y enlaces', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        MaterialApp(
          home: MonumentsScreen(repository: _FakeRepository(monuments)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 lugares'), findsOneWidget);

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Museos'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Museos'));
      await tester.pumpAndSettle();
      expect(find.text('1 lugar'), findsOneWidget);
      expect(find.text('Iglesia de San Pablo'), findsNothing);

      await tester.tap(find.text('Museo del Foro de Caesaraugusta'));
      await tester.pumpAndSettle();
      expect(find.text('Horario'), findsOneWidget);
      expect(find.textContaining('Lunes cerrado'), findsOneWidget);
      expect(find.text('Entrada: 3 euros'), findsOneWidget);
      expect(find.text('Siglo I a.C. - Siglo I d.C.'), findsOneWidget);
      for (final label in ['Cómo llegar', 'Llamar', 'Más información']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // Aviso de origen con la fecha de esta ficha, como en las actividades.
      expect(
        find.text(
          'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de '
          'Cultura). Información actualizada por última vez el 5 de junio '
          'de 2018.',
        ),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('el listado cita el origen con la fecha más reciente', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(
        MaterialApp(
          home: MonumentsScreen(repository: _FakeRepository(monuments)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Origen de los datos'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(
          'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de '
          'Cultura). Información actualizada por última vez el 10 de '
          'febrero de 2023.',
        ),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('sin fecha oficial el aviso solo cita el origen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      await tester.pumpWidget(
        MaterialApp(
          home: MonumentDetailScreen(
            monument: monuments.firstWhere((m) => m.id == 'monumento-9'),
          ),
        ),
      );
      expect(
        find.text(
          'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de '
          'Cultura).',
        ),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('monumentos ya no mezcla las rutas', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MonumentsScreen(repository: _FakeRepository(monuments)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rutas para descubrir Zaragoza'), findsNothing);
      expect(find.text('Zaragoza romana'), findsNothing);
    });

    testWidgets('si no hay conexión ni datos guardados, ofrece reintentar', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MonumentsScreen(repository: _FakeRepository(null)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('la pantalla de rutas lista las cinco rutas', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      await tester.pumpWidget(
        MaterialApp(home: RoutesScreen(repository: _FakeRepository(monuments))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rutas'), findsOneWidget); // título de la pantalla
      expect(find.text('Rutas culturales'), findsOneWidget);
      expect(find.text('Rutas naturales'), findsOneWidget);
      for (final title in [
        'Zaragoza romana',
        'Mudéjar Patrimonio Mundial',
        'La Zaragoza del Renacimiento',
        'Zaragoza de Goya',
        'Los Sitios de Zaragoza',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      await tester.tap(find.text('Zaragoza romana'));
      await tester.pumpAndSettle();
      expect(find.byType(RouteDetailScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('las rutas naturales aún no tienen contenido', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        MaterialApp(home: RoutesScreen(repository: _FakeRepository(monuments))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rutas naturales'));
      await tester.pumpAndSettle();
      expect(find.text('Muy pronto'), findsOneWidget);
      expect(find.text('Zaragoza romana'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets(
      'la portada tiene botones independientes de Monumentos y Rutas',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1800));
        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(monumentsRepository: _FakeRepository(monuments)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rutas'));
        await tester.pumpAndSettle();
        expect(find.byType(RoutesScreen), findsOneWidget);
        expect(find.byType(MonumentsScreen), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monumentos'));
        await tester.pumpAndSettle();
        expect(find.byType(MonumentsScreen), findsOneWidget);
        expect(find.byType(RoutesScreen), findsNothing);
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets('la pantalla principal lleva a Monumentos y museos', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(monumentsRepository: _FakeRepository(monuments)),
        ),
      );
      await tester.tap(find.text('Monumentos'));
      await tester.pumpAndSettle();
      expect(find.text('Monumentos y museos'), findsOneWidget);
      expect(find.text('Iglesia de San Pablo'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
