import 'package:flutter_test/flutter_test.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/reminders.dart';

CulturalEvent _event({
  String date = '2026-10-10',
  List<String> slots = const [],
  String place = 'Teatro Principal',
}) {
  return CulturalEvent(
    id: 'e1',
    title: 'Noche de jazz',
    description: 'Descripción',
    category: CulturalCategory.musica,
    date: date,
    time: slots.isEmpty ? '' : slots.first.split('–').first,
    place: place,
    address: 'Calle Mayor 1',
    officialUrl: 'https://www.zaragoza.es/sede/servicio/cultura/evento/1',
    timeSlots: slots,
  );
}

void main() {
  group('Avisos de favoritos', () {
    final now = DateTime(2026, 10, 5, 12);

    test('avisa la tarde anterior a las 18:00', () {
      final plans = planReminders([
        const ReminderCandidate(
          title: 'Noche de jazz',
          date: '2026-10-10',
          timeLabel: '20:30',
          place: 'Teatro Principal',
        ),
      ], now: now);
      expect(plans, hasLength(1));
      expect(plans.first.when, DateTime(2026, 10, 9, 18));
      expect(plans.first.title, 'Mañana: Noche de jazz');
      expect(plans.first.body, '20:30 · Teatro Principal');
    });

    test('no avisa de momentos que ya pasaron', () {
      final plans = planReminders([
        const ReminderCandidate(title: 'Hoy', date: '2026-10-05'),
        const ReminderCandidate(title: 'Pasada', date: '2026-10-01'),
        // Mañana: el aviso habría sido hoy a las 18:00 (aún no ha llegado).
        const ReminderCandidate(title: 'Mañana', date: '2026-10-06'),
      ], now: now);
      expect(plans.map((p) => p.title), ['Mañana: Mañana']);
    });

    test('si ya pasaron las 18:00 no avisa de mañana', () {
      final plans = planReminders(const [
        ReminderCandidate(title: 'Mañana', date: '2026-10-06'),
      ], now: DateTime(2026, 10, 5, 19));
      expect(plans, isEmpty);
    });

    test('ordena por fecha, numera y limita la cantidad', () {
      final candidates = [
        for (var i = 0; i < 100; i++)
          ReminderCandidate(
            title: 'A$i',
            date: DateTime(
              2026,
              11,
              1,
            ).add(Duration(days: 99 - i)).toIso8601String().split('T').first,
          ),
      ];
      final plans = planReminders(candidates, now: now);
      expect(plans, hasLength(maxReminders));
      expect(plans.first.id, 1);
      expect(plans.first.when.isBefore(plans.last.when), isTrue);
    });

    test('ignora fechas inválidas', () {
      final plans = planReminders(const [
        ReminderCandidate(title: 'X', date: 'no-es-fecha'),
      ], now: now);
      expect(plans, isEmpty);
    });
  });

  group('Compartir', () {
    test('incluye título, fecha, horario, lugar y enlace oficial', () {
      final text = buildShareText(_event(slots: ['20:30–22:00']));
      expect(text, contains('Noche de jazz'));
      expect(text, contains('sábado, 10 de octubre'));
      expect(text, contains('20:30–22:00'));
      expect(text, contains('Teatro Principal'));
      expect(
        text,
        contains('https://www.zaragoza.es/sede/servicio/cultura/evento/1'),
      );
    });

    test('el enlace a la app va antes que el enlace oficial', () {
      final text = buildShareText(_event(slots: ['20:30']));
      final app = text.indexOf('/app');
      final official = text.indexOf('zaragoza.es/sede');
      expect(app, greaterThan(0));
      expect(official, greaterThan(app));
      expect(text, contains('Zaragoza Cultura'));
    });

    test('sin horario no deja huecos ni escribe "Horario por confirmar"', () {
      final text = buildShareText(_event());
      expect(text, isNot(contains('Horario')));
      expect(text, isNot(contains('\n\n\n')));
    });
  });

  group('Calendario', () {
    test('usa la franja horaria de la actividad', () {
      final window = calendarWindowFor(_event(slots: ['20:30–22:00']));
      expect(window.allDay, isFalse);
      expect(window.start, DateTime(2026, 10, 10, 20, 30));
      expect(window.end, DateTime(2026, 10, 10, 22));
    });

    test('sin hora de fin dura una hora', () {
      final window = calendarWindowFor(_event(slots: ['19:00']));
      expect(window.end.difference(window.start), const Duration(hours: 1));
    });

    test('con dos franjas usa la primera', () {
      final window = calendarWindowFor(
        _event(slots: ['10:00–14:00', '16:00–20:00']),
      );
      expect(window.start, DateTime(2026, 10, 10, 10));
      expect(window.end, DateTime(2026, 10, 10, 14));
    });

    test('sin horario es un evento de todo el día', () {
      final window = calendarWindowFor(_event());
      expect(window.allDay, isTrue);
      expect(window.start, DateTime(2026, 10, 10));
    });
  });
}
