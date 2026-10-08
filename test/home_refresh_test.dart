import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/monuments.dart';
import 'package:zaragoza_cultura_app/useful_services.dart';

final _now = DateTime(2026, 10, 8, 10);

CulturalEvent _event(String title) => CulturalEvent(
  id: 'e1',
  title: title,
  description: 'Texto',
  category: CulturalCategory.musica,
  date: '2026-10-08',
  time: '20:00',
  place: 'Auditorio',
  officialUrl: 'https://www.zaragoza.es',
);

class _Events extends ZaragozaEventsRepository {
  final List<CulturalEvent> cached;
  final List<CulturalEvent>? fresh;
  int downloads = 0;

  _Events({required this.cached, required this.fresh});

  @override
  Future<List<CulturalEvent>> loadCached() async => cached;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async {
    downloads++;
    return fresh;
  }
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

Widget _home(_Events events) => MaterialApp(
  home: HomeScreen(
    repository: events,
    monumentsRepository: const _NoMonuments(),
    servicesRepository: const _NoServices(),
    weatherRepository: const _NoWeather(),
    clock: () => _now,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la portada renueva lo guardado con lo que da el servidor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    final events = _Events(
      cached: [_event('Texto antiguo')],
      fresh: [_event('Texto nuevo')],
    );
    await tester.pumpWidget(_home(events));
    await tester.pumpAndSettle();
    expect(find.text('Texto nuevo'), findsOneWidget);
    expect(find.text('Texto antiguo'), findsNothing);
    expect(events.downloads, 1);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('sin conexión se queda con lo guardado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    final events = _Events(cached: [_event('Texto antiguo')], fresh: null);
    await tester.pumpWidget(_home(events));
    await tester.pumpAndSettle();
    expect(find.text('Texto antiguo'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
