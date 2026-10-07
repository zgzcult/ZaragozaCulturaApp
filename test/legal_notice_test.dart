import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/legal_notice.dart';
import 'package:zaragoza_cultura_app/main.dart';

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

CulturalEvent _event({String date = '', String updatedAt = '2026-10-05'}) {
  return CulturalEvent(
    id: 'e$date',
    title: 'Concierto de prueba',
    description: '',
    category: CulturalCategory.musica,
    date: date.isEmpty ? _today() : date,
    time: '',
    place: 'Sala',
    officialUrl: 'https://www.zaragoza.es/sede/servicio/cultura/evento/1',
    updatedAt: updatedAt,
  );
}

class _Repo extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _Repo(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('la fecha se escribe en español y se toma la más reciente', () {
    expect(longDate(DateTime(2026, 10, 5)), '5 de octubre de 2026');
    expect(
      latestDate(['2026-09-30', '2026-10-05', '', 'no-es-fecha']),
      DateTime(2026, 10, 5),
    );
    expect(latestDate(['', 'xx']), isNull);
    expect(latestDate(const []), isNull);
  });

  test('el origen cita al Ayuntamiento con la fecha de actualización', () {
    expect(
      originText(DateTime(2026, 10, 5)),
      'Origen de los datos: Ayuntamiento de Zaragoza. '
      'Información actualizada por última vez el 5 de octubre de 2026.',
    );
    expect(originText(null), 'Origen de los datos: Ayuntamiento de Zaragoza.');
  });

  testWidgets('el pie de actividades solo cita el origen y la fecha', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReuseNotice(
            service: 'Servicio de Cultura',
            updated: DateTime(2026, 10, 5),
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de Cultura). '
        'Información actualizada por última vez el 5 de octubre de 2026.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('sin alterar su sentido'), findsNothing);
    expect(find.textContaining('patrocinada'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('las demás condiciones de reutilización están en Acerca de', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 3200));
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    expect(find.textContaining('sin alterar su sentido'), findsOneWidget);
    expect(find.textContaining('no está patrocinada'), findsWidgets);
    expect(
      find.text('Condiciones generales para la reutilización'),
      findsOneWidget,
    );
    expect(legalNoticeUrl, 'https://www.zaragoza.es/sede/portal/aviso-legal');
    await tester.binding.setSurfaceSize(null);
  });

  group('en la pantalla de actividades', () {
    testWidgets('sale al final de la lista del día', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      await tester.pumpWidget(
        ZaragozaCulturaApp(repository: _Repo([_event()])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Origen de los datos'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('(Servicio de Cultura)'), findsOneWidget);
      expect(find.textContaining('5 de octubre de 2026'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('en Favoritos no sale el aviso de origen', (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_event_ids': [_event().id],
      });
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(
        MaterialApp(home: AgendaScreen(repository: _Repo([_event()]))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();
      expect(find.text('Tus favoritos'), findsOneWidget);
      expect(find.textContaining('Origen de los datos'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('no sale en un día sin actividades', (tester) async {
      await tester.pumpWidget(
        ZaragozaCulturaApp(repository: _Repo([_event(date: '2030-01-01')])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(find.text('No hay actividades para este día.'), findsOneWidget);
      expect(find.textContaining('Origen de los datos'), findsNothing);
    });

    testWidgets('la ficha lleva el aviso con la fecha de la actividad', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: _event(),
            isFavorite: false,
            onToggleFavorite: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de '
          'Cultura). Información actualizada por última vez el 5 de octubre '
          'de 2026.',
        ),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('una actividad que no es del Ayuntamiento no lleva el aviso', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      final propia = CulturalEvent(
        id: 'p1',
        title: 'Concierto propio',
        description: '',
        category: CulturalCategory.musica,
        date: _today(),
        time: '',
        place: 'Sala',
        officialUrl: 'https://example.org',
        source: 'propia',
      );
      expect(propia.fromAyuntamiento, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: propia,
            isFavorite: false,
            onToggleFavorite: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Origen de los datos'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    test('el origen se lee del dato y por defecto es el Ayuntamiento', () {
      final base = {'id': '1', 'title': 'x', 'date': '2026-10-10'};
      expect(CulturalEvent.fromJson(base).fromAyuntamiento, isTrue);
      expect(
        CulturalEvent.fromJson({...base, 'source': 'ayuntamiento'})
            .fromAyuntamiento,
        isTrue,
      );
      expect(
        CulturalEvent.fromJson({...base, 'source': 'propia'}).fromAyuntamiento,
        isFalse,
      );
      expect(
        CulturalEvent.fromJson({...base, 'source': 'propia'})
            .withTimeSlots(const ['10:00'])
            .fromAyuntamiento,
        isFalse,
      );
    });
  });
}
