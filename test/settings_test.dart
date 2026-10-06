import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/nearby.dart';

class _Location extends LocationService {
  final bool granted;
  final LocationStatus onRequest;
  int requests = 0;
  int settingsOpened = 0;

  _Location({required this.granted, this.onRequest = LocationStatus.ok});

  @override
  Future<LocationResult> locate({required bool askPermission}) async =>
      const LocationResult(LocationStatus.denied);

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<LocationStatus> requestPermission() async {
    requests++;
    return onRequest;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

Widget _settings(_Location location) => MaterialApp(
  home: SettingsScreen(
    remindersEnabled: false,
    onRemindersChanged: (_) async => true,
    locationService: location,
  ),
);

Switch _locationSwitch(WidgetTester tester) {
  final tile = find.widgetWithText(
    SwitchListTile,
    'Ubicación para «Cerca de mí»',
  );
  return tester.widget<SwitchListTile>(tile).onChanged == null
      ? throw StateError('interruptor desactivado')
      : tester.widget<Switch>(
          find.descendant(of: tile, matching: find.byType(Switch)),
        );
}

CulturalEvent _event({
  String moreInfoUrl = '',
  String officialUrl = 'https://www.zaragoza.es/sede/servicio/cultura/evento/1',
}) {
  return CulturalEvent(
    id: 'e',
    title: 'Actividad',
    description: '',
    category: CulturalCategory.musica,
    date: '2026-10-10',
    time: '',
    place: 'Sala',
    officialUrl: officialUrl,
    moreInfoUrl: moreInfoUrl,
  );
}

class _Repo extends ZaragozaEventsRepository {
  const _Repo();

  @override
  Future<List<CulturalEvent>> loadCached() async => [_event()];

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => [_event()];
}

void main() {
  group('Interruptor de ubicación', () {
    testWidgets('refleja si ya hay permiso', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(_settings(_Location(granted: true)));
      await tester.pumpAndSettle();
      expect(_locationSwitch(tester).value, isTrue);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('al activarlo pide el permiso sin salir de la app', (
      tester,
    ) async {
      final location = _Location(granted: false);
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(_settings(location));
      await tester.pumpAndSettle();
      expect(_locationSwitch(tester).value, isFalse);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Ubicación para «Cerca de mí»'),
      );
      await tester.pumpAndSettle();

      expect(location.requests, 1);
      expect(_locationSwitch(tester).value, isTrue);
      expect(location.settingsOpened, 0);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('si el permiso está bloqueado ofrece abrir los ajustes', (
      tester,
    ) async {
      final location = _Location(
        granted: false,
        onRequest: LocationStatus.deniedForever,
      );
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(_settings(location));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Ubicación para «Cerca de mí»'),
      );
      await tester.pumpAndSettle();

      expect(_locationSwitch(tester).value, isFalse);
      expect(find.textContaining('Has bloqueado el permiso'), findsOneWidget);
      await tester.tap(find.text('Abrir ajustes'));
      await tester.pumpAndSettle();
      expect(location.settingsOpened, 1);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('si se rechaza, avisa y el interruptor sigue apagado', (
      tester,
    ) async {
      final location = _Location(
        granted: false,
        onRequest: LocationStatus.denied,
      );
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(_settings(location));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Ubicación para «Cerca de mí»'),
      );
      await tester.pumpAndSettle();

      expect(_locationSwitch(tester).value, isFalse);
      expect(
        find.text('No se concedió el permiso de ubicación.'),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('desactivarlo remite a los ajustes del teléfono', (
      tester,
    ) async {
      final location = _Location(granted: true);
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(_settings(location));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Ubicación para «Cerca de mí»'),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Para desactivar la ubicación'),
        findsOneWidget,
      );
      expect(
        _locationSwitch(tester).value,
        isTrue,
      ); // el permiso sigue concedido
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Enlace «Más información»', () {
    const ficha = 'https://www.zaragoza.es/sede/servicio/cultura/evento/1';

    test('usa el enlace de la actividad si es una web concreta', () {
      expect(
        moreInfoTarget(_event(moreInfoUrl: 'https://iaacc.es')),
        'https://iaacc.es',
      );
    });

    test('si es una página del portal, usa la ficha de la agenda', () {
      for (final url in [
        'https://www.zaragoza.es/sede/portal/museos/centro-historias/',
        'http://zaragoza.es/sede/portal/servicios-sociales/mujer/',
        'https://WWW.ZARAGOZA.ES/sede/PORTAL/cultura',
      ]) {
        expect(moreInfoTarget(_event(moreInfoUrl: url)), ficha, reason: url);
      }
    });

    test('sin enlace usa la ficha de la agenda', () {
      expect(moreInfoTarget(_event()), ficha);
    });

    test('otras páginas de zaragoza.es sí se conservan', () {
      const url =
          'https://www.zaragoza.es/sede/servicio/equipamiento/3031?open=actividades';
      expect(moreInfoTarget(_event(moreInfoUrl: url)), url);
    });
  });

  testWidgets('Ajustes se abre desde la pantalla principal', (tester) async {
    SharedPreferences.setMockInitialValues({'reminders_enabled': true});
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    await tester.pumpWidget(const ZaragozaCulturaApp(repository: _Repo()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    // Refleja que los avisos estaban activados.
    final reminders = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile).first,
    );
    expect(reminders.value, isTrue);
    await tester.binding.setSurfaceSize(null);
  });

  test('desactivar los avisos lo guarda en el teléfono', () async {
    SharedPreferences.setMockInitialValues({'reminders_enabled': true});
    expect(await loadRemindersEnabled(), isTrue);
    expect(
      await setFavoriteReminders(false, repository: const _Repo()),
      isTrue,
    );
    expect(await loadRemindersEnabled(), isFalse);
  });
}
