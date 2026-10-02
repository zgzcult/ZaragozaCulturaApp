import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';

String _key(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

CulturalEvent _event(
  String id,
  String title, {
  String date = '2026-10-10',
  String? time,
  String runStart = '',
  String runEnd = '',
  String place = 'Sala',
}) {
  return CulturalEvent(
    id: id,
    title: title,
    description: '',
    category: CulturalCategory.musica,
    date: date,
    time: time ?? '',
    place: place,
    officialUrl: 'https://www.zaragoza.es',
    runStart: runStart,
    runEnd: runEnd,
    timeSlots: time == null ? const [] : [time],
  );
}

class _FakeRepository extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _FakeRepository(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

void main() {
  group('isLongRunning', () {
    test('más de una semana es larga duración', () {
      expect(
        _event(
          'a',
          'x',
          runStart: '2026-10-01',
          runEnd: '2026-10-08',
        ).isLongRunning,
        isTrue,
      );
    });

    test('menos de una semana no lo es', () {
      expect(
        _event(
          'a',
          'x',
          runStart: '2026-10-01',
          runEnd: '2026-10-07',
        ).isLongRunning,
        isFalse,
      );
      expect(
        _event(
          'a',
          'x',
          runStart: '2026-10-01',
          runEnd: '2026-10-01',
        ).isLongRunning,
        isFalse,
      );
    });

    test('sin fechas de duración se considera corta', () {
      expect(_event('a', 'x').isLongRunning, isFalse);
    });
  });

  group('compareEventsWithinDay', () {
    test('cortas con hora, cortas sin hora y al final las largas', () {
      final long = _event(
        'l',
        'Exposición',
        time: '10:00',
        runStart: '2026-09-01',
        runEnd: '2026-12-31',
      );
      final shortLate = _event('s2', 'Concierto tarde', time: '21:00');
      final shortEarly = _event('s1', 'Concierto pronto', time: '12:00');
      final shortNoTime = _event('s3', 'Mercadillo');
      final list = [long, shortNoTime, shortLate, shortEarly]
        ..sort(compareEventsWithinDay);
      expect(list.map((e) => e.id), ['s1', 's2', 's3', 'l']);
    });

    test(
      'una exposición a las 09:00 va detrás de un concierto a las 22:00',
      () {
        final expo = _event(
          'l',
          'Expo',
          time: '09:00',
          runStart: '2026-09-01',
          runEnd: '2026-12-31',
        );
        final concert = _event('c', 'Concierto', time: '22:00');
        expect(compareEventsWithinDay(concert, expo), lessThan(0));
      },
    );
  });

  test(
    'sin fechas del servidor, la duración se calcula con los días cargados',
    () async {
      final raw = <Map<String, dynamic>>[
        for (var day = 1; day <= 12; day++)
          {
            'id': 'exp-$day',
            'title': 'Exposición larga',
            'place': 'Museo',
            'category': 'exposiciones',
            'date': '2026-10-${day.toString().padLeft(2, '0')}',
            'time': '10:00',
            'endTime': '14:00',
          },
        {
          'id': 'con-1',
          'title': 'Concierto',
          'place': 'Auditorio',
          'category': 'musica',
          'date': '2026-10-05',
          'time': '20:00',
        },
      ];
      SharedPreferences.setMockInitialValues({
        'cached_events_json': jsonEncode(raw),
      });
      final events = await const ZaragozaEventsRepository().loadCached();
      final expo = events.firstWhere((e) => e.title == 'Exposición larga');
      final concert = events.firstWhere((e) => e.title == 'Concierto');
      expect(expo.isLongRunning, isTrue);
      expect(concert.isLongRunning, isFalse);
    },
  );

  test('con fechas reales del servidor, una exposición que acaba pronto sigue siendo larga', () async {
    SharedPreferences.setMockInitialValues({
      'cached_events_json': jsonEncode([
        {
          'id': 'e1',
          'title': 'Exposición casi acabada',
          'place': 'Museo',
          'category': 'exposiciones',
          'date': '2026-10-09',
          'time': '10:00',
          'runStartDate': '2026-06-01',
          'runEndDate': '2026-10-11',
        },
      ]),
    });
    final events = await const ZaragozaEventsRepository().loadCached();
    expect(events.single.isLongRunning, isTrue);
  });

  testWidgets('Agenda: las actividades cortas salen antes que las largas', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final today = _key(DateTime.now());
    final repo = _FakeRepository([
      _event(
        'l',
        'Exposición de larga duración',
        date: today,
        time: '09:00',
        runStart: '2026-01-01',
        runEnd: '2027-01-01',
      ),
      _event('s1', 'Concierto de tarde', date: today, time: '20:00'),
      _event('s0', 'Taller de mañana', date: today, time: '10:00'),
    ]);

    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(ZaragozaCulturaApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    final taller = tester.getTopLeft(find.text('Taller de mañana')).dy;
    final concierto = tester.getTopLeft(find.text('Concierto de tarde')).dy;
    final expo = tester
        .getTopLeft(find.text('Exposición de larga duración'))
        .dy;
    expect(taller, lessThan(concierto));
    expect(concierto, lessThan(expo));

    await tester.binding.setSurfaceSize(null);
  });

  test('Búsqueda: a igual relevancia, primero las de pocos días', () {
    final today = DateTime(2026, 10, 5);
    final results = searchEvents(
      [
        _event(
          'l',
          'Festival de jazz exposición',
          date: '2026-10-06',
          runStart: '2026-09-01',
          runEnd: '2026-12-01',
        ),
        _event(
          's',
          'Festival de jazz en la plaza',
          date: '2026-10-09',
          runStart: '2026-10-09',
          runEnd: '2026-10-10',
        ),
      ],
      'jazz',
      today: today,
    );
    expect(results.map((r) => r.event.id), ['s', 'l']);
  });
}
