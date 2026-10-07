/// Avisos de favoritos: notificaciones locales programadas.
///
/// El aviso llega la tarde anterior a la actividad (18:00, hora de Zaragoza).
/// Todo ocurre en el dispositivo: no se envía nada a ningún servidor.
///
/// Además se lleva un pequeño registro de los avisos (en el propio teléfono)
/// para el buzón de la pantalla principal: los que ya han llegado y siguen sin
/// leer.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Datos mínimos de una actividad para poder avisar de ella.
class ReminderCandidate {
  /// Identificador de la actividad: al pulsar el aviso se abre su ficha.
  final String eventId;
  final String title;

  /// Fecha de la actividad, AAAA-MM-DD.
  final String date;
  final String timeLabel;
  final String place;

  const ReminderCandidate({
    this.eventId = '',
    required this.title,
    required this.date,
    this.timeLabel = '',
    this.place = '',
  });
}

/// Un aviso ya calculado.
class ReminderPlan {
  final int id;

  /// Actividad que origina el aviso.
  final String eventId;

  /// Fecha y hora del aviso (hora local de Zaragoza).
  final DateTime when;
  final String title;
  final String body;

  const ReminderPlan({
    required this.id,
    this.eventId = '',
    required this.when,
    required this.title,
    required this.body,
  });
}

/// Hora del día anterior a la que se envía el aviso.
const int reminderHour = 18;

// --- Aviso semanal: sugerencias para el fin de semana ----------------------

/// Lo que lleva el aviso semanal para que, al pulsarlo, se abra la pantalla
/// «Sugerencias fin de semana» (los de favoritos llevan el id de la actividad).
const String weekendPayload = 'weekend';

/// Identificador del aviso semanal (los de favoritos usan del 1 al 60).
const int weekendReminderId = 9000;

/// Hora del jueves a la que llega (una hora antes que los de favoritos, para
/// que no coincidan).
const int weekendReminderHour = 17;

const String _weekendKey = 'weekend_reminder_enabled';

/// Próximo jueves a las 17:00, estrictamente después de [now].
DateTime nextWeekendReminder(DateTime now) {
  var when = DateTime(now.year, now.month, now.day, weekendReminderHour);
  while (when.weekday != DateTime.thursday || !when.isAfter(now)) {
    when = DateTime(when.year, when.month, when.day + 1, weekendReminderHour);
  }
  return when;
}

/// ¿Está activado el aviso semanal del fin de semana?
Future<bool> loadWeekendReminderEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_weekendKey) ?? false;
}

/// Activa o desactiva el aviso semanal. Al activar pide el permiso de
/// notificaciones. Devuelve si el cambio se pudo hacer.
Future<bool> setWeekendReminder(bool enabled) async {
  final service = ReminderService();
  if (enabled && !await service.requestPermission()) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_weekendKey, enabled);
  await service.syncWeekend();
  return true;
}

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
        eventId: candidate.eventId,
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
        eventId: limited[i].eventId,
        when: limited[i].when,
        title: limited[i].title,
        body: limited[i].body,
      ),
  ];
}

// ---------------------------------------------------------------------------
// Buzón de avisos
// ---------------------------------------------------------------------------

/// Un aviso del registro: programado, o ya llegado (leído o no).
class ReminderEntry {
  final String eventId;
  final DateTime when;
  final String title;
  final String body;
  final bool read;

  const ReminderEntry({
    required this.eventId,
    required this.when,
    required this.title,
    required this.body,
    this.read = false,
  });

  ReminderEntry asRead() => ReminderEntry(
    eventId: eventId,
    when: when,
    title: title,
    body: body,
    read: true,
  );

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'when': when.toIso8601String(),
    'title': title,
    'body': body,
    'read': read,
  };

  static ReminderEntry? fromJson(dynamic json) {
    if (json is! Map) return null;
    final when = DateTime.tryParse((json['when'] ?? '').toString());
    final eventId = (json['eventId'] ?? '').toString();
    if (when == null || eventId.isEmpty) return null;
    return ReminderEntry(
      eventId: eventId,
      when: when,
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      read: json['read'] == true,
    );
  }
}

/// Días que un aviso ya llegado se conserva en el buzón.
const int reminderLogDays = 14;

/// Registro actualizado: se conservan los avisos que ya llegaron (hasta
/// [reminderLogDays] días) y los programados se sustituyen por [plans].
List<ReminderEntry> mergeReminderLog(
  List<ReminderEntry> existing,
  List<ReminderPlan> plans, {
  required DateTime now,
}) {
  final oldest = now.subtract(const Duration(days: reminderLogDays));
  final merged = <ReminderEntry>[
    for (final entry in existing)
      if (!entry.when.isAfter(now) && entry.when.isAfter(oldest)) entry,
    for (final plan in plans)
      if (plan.eventId.isNotEmpty && plan.when.isAfter(now))
        ReminderEntry(
          eventId: plan.eventId,
          when: plan.when,
          title: plan.title,
          body: plan.body,
        ),
  ];
  merged.sort((a, b) => b.when.compareTo(a.when));
  return merged;
}

/// Avisos que ya han llegado, del más reciente al más antiguo.
List<ReminderEntry> deliveredReminders(
  List<ReminderEntry> log, {
  required DateTime now,
}) {
  final oldest = now.subtract(const Duration(days: reminderLogDays));
  return [
    for (final entry in log)
      if (!entry.when.isAfter(now) && entry.when.isAfter(oldest)) entry,
  ]..sort((a, b) => b.when.compareTo(a.when));
}

/// Registro de avisos guardado en el teléfono.
class ReminderInbox {
  const ReminderInbox._();

  static const String _key = 'reminder_log';

  /// Número de avisos llegados y sin leer. La campana de la pantalla
  /// principal lo escucha.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  static Future<List<ReminderEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (ReminderEntry.fromJson(item) case final entry?) entry,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _save(List<ReminderEntry> log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final entry in log) entry.toJson()]),
    );
  }

  /// Actualiza el registro con los avisos recién programados.
  static Future<void> record(List<ReminderPlan> plans, {DateTime? now}) async {
    now ??= DateTime.now();
    await _save(mergeReminderLog(await load(), plans, now: now));
    await refresh(now: now);
  }

  /// Avisos llegados (para el buzón).
  static Future<List<ReminderEntry>> delivered({DateTime? now}) async =>
      deliveredReminders(await load(), now: now ?? DateTime.now());

  /// Recalcula cuántos avisos hay sin leer.
  static Future<int> refresh({DateTime? now}) async {
    final pending = (await delivered(now: now)).where((e) => !e.read).length;
    unread.value = pending;
    return pending;
  }

  /// Marca como leído el aviso de una actividad (o todos si no se indica).
  static Future<void> markRead({String? eventId, DateTime? now}) async {
    now ??= DateTime.now();
    final log = await load();
    await _save([
      for (final entry in log)
        if (!entry.when.isAfter(now) &&
            (eventId == null || entry.eventId == eventId))
          entry.asRead()
        else
          entry,
    ]);
    await refresh(now: now);
  }
}

// ---------------------------------------------------------------------------
// Notificaciones del sistema
// ---------------------------------------------------------------------------

/// Programa los avisos en el dispositivo (Android).
class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Se llama cuando el usuario pulsa un aviso con la app abierta o en
  /// segundo plano: con el identificador de la actividad o, si es el aviso
  /// semanal, con [weekendPayload].
  static void Function(String eventId)? onOpen;

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

  static const NotificationDetails _weekendDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'weekend_suggestions',
      'Sugerencias para el fin de semana',
      channelDescription:
          'Cada jueves, un aviso con las sugerencias para el fin de semana.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> _init() async {
    if (!_supported) return false;
    if (_ready) return true;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final eventId = response.payload ?? '';
        if (eventId.isNotEmpty) onOpen?.call(eventId);
      },
    );
    _ready = true;
    return true;
  }

  /// Si la app se abrió al pulsar un aviso, el identificador de su
  /// actividad; si no, null. También deja preparada la escucha de avisos.
  Future<String?> launchEventId() async {
    try {
      if (!await _init()) return null;
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      final eventId = details.notificationResponse?.payload ?? '';
      return eventId.isEmpty ? null : eventId;
    } catch (error) {
      debugPrint('REMINDERS launch error: $error');
      return null;
    }
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
      await ReminderInbox.record(plans);
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
          payload: plan.eventId,
        );
      }
      // cancelAll() también quita el aviso semanal: se vuelve a programar.
      await syncWeekend();
    } catch (error) {
      debugPrint('REMINDERS sync error: $error');
    }
  }

  /// Programa (o quita) el aviso de cada jueves, según lo elegido en Ajustes.
  Future<void> syncWeekend() async {
    try {
      if (!await _init()) return;
      await _plugin.cancel(id: weekendReminderId);
      if (!await loadWeekendReminderEnabled()) return;
      final zone = tz.getLocation('Europe/Madrid');
      // Hora de Zaragoza «de reloj», sin zona, para calcular el jueves.
      final madrid = tz.TZDateTime.now(zone);
      final when = nextWeekendReminder(
        DateTime(
          madrid.year,
          madrid.month,
          madrid.day,
          madrid.hour,
          madrid.minute,
        ),
      );
      await _plugin.zonedSchedule(
        id: weekendReminderId,
        title: 'Planes para el fin de semana',
        body: 'Ya tienes tus sugerencias para el sábado y el domingo.',
        scheduledDate: tz.TZDateTime(
          zone,
          when.year,
          when.month,
          when.day,
          when.hour,
        ),
        notificationDetails: _weekendDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Se repite cada semana, el mismo día y a la misma hora.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: weekendPayload,
      );
    } catch (error) {
      debugPrint('REMINDERS weekend error: $error');
    }
  }

  /// Cancela todos los avisos.
  Future<void> cancelAll() => sync(const <ReminderPlan>[]);
}
