/// Avisos de favoritos: notificaciones locales programadas.
///
/// El aviso llega la tarde anterior a la actividad (18:00, hora de Zaragoza).
/// Todo ocurre en el dispositivo: no se envía nada a ningún servidor.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Datos mínimos de una actividad para poder avisar de ella.
class ReminderCandidate {
  final String title;

  /// Fecha de la actividad, AAAA-MM-DD.
  final String date;
  final String timeLabel;
  final String place;

  const ReminderCandidate({
    required this.title,
    required this.date,
    this.timeLabel = '',
    this.place = '',
  });
}

/// Un aviso ya calculado.
class ReminderPlan {
  final int id;

  /// Fecha y hora del aviso (hora local de Zaragoza).
  final DateTime when;
  final String title;
  final String body;

  const ReminderPlan({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });
}

/// Hora del día anterior a la que se envía el aviso.
const int reminderHour = 18;

/// Máximo de avisos programados a la vez (Android limita las alarmas).
const int maxReminders = 60;

/// Calcula qué avisos programar: uno por actividad, la tarde anterior,
/// solo si ese momento todavía no ha pasado. Ordenados por fecha.
List<ReminderPlan> planReminders(
  List<ReminderCandidate> candidates, {
  required DateTime now,
}) {
  final plans = <ReminderPlan>[];
  for (final candidate in candidates) {
    final day = DateTime.tryParse(candidate.date);
    if (day == null) continue;
    final when = DateTime(day.year, day.month, day.day - 1, reminderHour);
    if (!when.isAfter(now)) continue;

    final details = <String>[
      if (candidate.timeLabel.isNotEmpty) candidate.timeLabel,
      if (candidate.place.isNotEmpty) candidate.place,
    ];
    plans.add(
      ReminderPlan(
        id: 0,
        when: when,
        title: 'Mañana: ${candidate.title}',
        body: details.isEmpty
            ? 'Una de tus actividades favoritas'
            : details.join(' · '),
      ),
    );
  }
  plans.sort((a, b) => a.when.compareTo(b.when));
  final limited = plans.take(maxReminders).toList();
  return [
    for (var i = 0; i < limited.length; i++)
      ReminderPlan(
        id: i + 1,
        when: limited[i].when,
        title: limited[i].title,
        body: limited[i].body,
      ),
  ];
}

/// Programa los avisos en el dispositivo (Android).
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'favorite_reminders',
      'Avisos de favoritos',
      channelDescription:
          'Te avisa la tarde anterior a tus actividades favoritas.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  Future<bool> _init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (_ready) return true;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
    return true;
  }

  /// Pide permiso para mostrar notificaciones. Devuelve si se concedió.
  Future<bool> requestPermission() async {
    try {
      if (!await _init()) return false;
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (error) {
      debugPrint('REMINDERS permission error: $error');
      return false;
    }
  }

  /// Sustituye los avisos programados por [plans].
  Future<void> sync(List<ReminderPlan> plans) async {
    try {
      if (!await _init()) return;
      await _plugin.cancelAll();
      final zone = tz.getLocation('Europe/Madrid');
      for (final plan in plans) {
        await _plugin.zonedSchedule(
          id: plan.id,
          title: plan.title,
          body: plan.body,
          scheduledDate: tz.TZDateTime(
            zone,
            plan.when.year,
            plan.when.month,
            plan.when.day,
            plan.when.hour,
            plan.when.minute,
          ),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (error) {
      debugPrint('REMINDERS sync error: $error');
    }
  }

  /// Cancela todos los avisos.
  Future<void> cancelAll() => sync(const <ReminderPlan>[]);
}
