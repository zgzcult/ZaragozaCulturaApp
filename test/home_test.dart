import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/useful_services.dart';

final _now = DateTime(2026, 10, 2, 17, 30); // viernes por la tarde

class _Events extends ZaragozaEventsRepository {
  const _Events();

  @override
  Future<List<CulturalEvent>> loadCached() async => [
    CulturalEvent(
      id: 'a',
      title: 'Concierto en marcha',
      description: '',
      category: CulturalCategory.musica,
      date: '2026-10-02',
      time: '17:00',
      place: 'Auditorio',
      officialUrl: 'https://www.zaragoza.es',
      timeSlots: const ['17:00'],
    ),
    CulturalEvent(
      id: 'b',
      title: 'Obra de la noche',
      description: '',
      category: CulturalCategory.teatro,
      date: '2026-10-02',
      time: '21:00',
      place: 'Teatro Principal',
      officialUrl: 'https://www.zaragoza.es',
      timeSlots: const ['21:00'],
    ),
  ];

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => null;
}

class _Monuments extends MonumentsRepository {
  const _Monuments();

  @override
  Future<List<Monument>> loadCached() async => const [];

  @override
  Future<List<Monument>?> fetchFresh() async => const [
    Monument(id: 'monumento-32', name: 'Basílica del Pilar', top: true),
    Monument(id: 'monumento-99', name: 'Casa normal'),
  ];
}

class _Services extends ServicesRepository {
  const _Services();

  @override
  Future<List<ServiceGroup>> loadCached() async => const [];

  @override
  Future<List<ServiceGroup>?> fetchFresh() async => const [
    ServiceGroup(
      id: 'farmacias-guardia',
      title: 'Farmacias de guardia',
      items: [
        ServiceItem(id: '1', name: 'Farmacia Uno'),
        ServiceItem(id: '2', name: 'Farmacia Dos'),
      ],
    ),
  ];
}

class _Weather extends WeatherRepository {
  final int? temp;

  const _Weather(this.temp);

  @override
  Future<int?> currentTemperature() async => temp;
}

Widget _home({int? temp = 17}) => MaterialApp(
  home: HomeScreen(
    repository: const _Events(),
    monumentsRepository: const _Monuments(),
    servicesRepository: const _Services(),
    weatherRepository: _Weather(temp),
    clock: () => _now,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el saludo cambia con la hora', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Buenos días');
    expect(greetingFor(DateTime(2026, 1, 1, 15)), 'Buenas tardes');
    expect(greetingFor(DateTime(2026, 1, 1, 22)), 'Buenas noches');
    expect(greetingFor(DateTime(2026, 1, 1, 3)), 'Buenas noches');
  });

  test('la fecha de la cabecera lleva la temperatura si se conoce', () {
    expect(headerDateLabel(_now, 17), 'VIERNES 2 DE OCTUBRE · 17°');
    expect(headerDateLabel(_now, null), 'VIERNES 2 DE OCTUBRE');
  });

  testWidgets('portada con saludo, accesos y bloques del día', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    await tester.pumpWidget(_home());
    await tester.pumpAndSettle();

    expect(find.text('Buenas tardes,\nmañ@'), findsOneWidget);
    expect(find.text('VIERNES 2 DE OCTUBRE · 17°'), findsOneWidget);
    expect(find.byTooltip('Ajustes'), findsOneWidget);
    for (final label in [
      'Agenda',
      'Para hoy',
      'Monumentos',
      'Rutas',
      'Servicios',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // Hoy te recomendamos: «Ahora» para lo que está en marcha, hora si no.
    expect(find.text('Hoy te recomendamos'), findsOneWidget);
    expect(find.text('Concierto en marcha'), findsOneWidget);
    expect(find.text('Ahora'), findsOneWidget);
    expect(find.text('21:00'), findsOneWidget);

    expect(find.text('Rutas para descubrir Zaragoza'), findsOneWidget);
    expect(find.text('Zaragoza romana'), findsOneWidget);

    // Solo los imprescindibles.
    expect(find.text('Imprescindibles'), findsOneWidget);
    expect(find.text('Basílica del Pilar'), findsOneWidget);
    expect(find.text('Casa normal'), findsNothing);

    expect(find.text('2 farmacias de guardia hoy'), findsOneWidget);
    await tester.tap(find.text('2 farmacias de guardia hoy'));
    await tester.pumpAndSettle();
    expect(find.text('Farmacia Uno'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('sin temperatura no muestra el dato', (tester) async {
    await tester.pumpWidget(_home(temp: null));
    await tester.pumpAndSettle();
    expect(find.text('VIERNES 2 DE OCTUBRE'), findsOneWidget);
  });

  testWidgets('una recomendación abre su ficha', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    await tester.pumpWidget(_home());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obra de la noche'));
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailScreen), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
