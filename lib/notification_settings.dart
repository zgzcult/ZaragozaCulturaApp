/// «Notificaciones»: los dos avisos que el usuario puede activar.
///  - Avisos de mis favoritos: la tarde anterior a cada actividad guardada.
///  - Sugerencias para el fin de semana: cada jueves.
library;

import 'package:flutter/material.dart';

import 'brand.dart';
import 'reminders.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final bool remindersEnabled;

  /// Activa o desactiva los avisos de favoritos. Devuelve si se pudo (al
  /// activar hace falta el permiso de notificaciones).
  final Future<bool> Function(bool enabled) onRemindersChanged;

  /// Lo mismo para el aviso semanal del fin de semana.
  final Future<bool> Function(bool enabled) onWeekendChanged;

  /// Estado inicial del aviso semanal (por defecto, lo guardado).
  final Future<bool> Function() loadWeekendEnabled;

  const NotificationSettingsScreen({
    super.key,
    required this.remindersEnabled,
    required this.onRemindersChanged,
    this.onWeekendChanged = setWeekendReminder,
    this.loadWeekendEnabled = loadWeekendReminderEnabled,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late bool _reminders = widget.remindersEnabled;
  bool _weekend = false;

  @override
  void initState() {
    super.initState();
    widget.loadWeekendEnabled().then((enabled) {
      if (mounted) setState(() => _weekend = enabled);
    });
  }

  Future<void> _toggle(
    bool value,
    Future<bool> Function(bool) change,
    void Function(bool) apply,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = await change(value);
    if (!mounted) return;
    if (done) {
      setState(() => apply(value));
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Para recibir avisos, permite las notificaciones de la app en los ajustes del teléfono.',
          ),
        ),
      );
    }
  }

  Widget _switch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.line),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: Icon(icon, color: Brand.navy),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Notificaciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _switch(
              icon: Icons.notifications_active_outlined,
              title: 'Avisos de mis favoritos',
              subtitle:
                  'Te avisamos un día antes para no perderte tus actividades '
                  'favoritas.',
              value: _reminders,
              onChanged: (value) => _toggle(
                value,
                widget.onRemindersChanged,
                (v) => _reminders = v,
              ),
            ),
            _switch(
              icon: Icons.celebration_outlined,
              title: 'Sugerencias para el fin de semana',
              subtitle:
                  'Cada jueves te avisamos de las recomendaciones para el '
                  'sábado y el domingo.',
              value: _weekend,
              onChanged: (value) =>
                  _toggle(value, widget.onWeekendChanged, (v) => _weekend = v),
            ),
          ],
        ),
      ),
    );
  }
}
