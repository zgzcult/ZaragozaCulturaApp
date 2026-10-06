/// «Envía tu evento»: formulario dentro de la app. El evento nos llega por
/// correo (asunto «Evento»), lo revisamos y, si procede, lo publicamos.
library;

import 'package:flutter/material.dart';

import 'brand.dart';
import 'suggestion.dart';

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _dateText(DateTime date) =>
    '${date.day} de ${_months[date.month - 1]} de ${date.year}';

/// Texto que recibimos por correo: los datos del evento, uno por línea, y
/// después la descripción. Los campos vacíos no aparecen.
String buildEventDescription({
  required DateTime date,
  String time = '',
  required String place,
  String price = '',
  String link = '',
  String organizer = '',
  required String description,
}) {
  final fields = {
    'Fecha': _dateText(date),
    'Hora': time,
    'Lugar': place,
    'Precio': price,
    'Enlace': link,
    'Organiza': organizer,
  };
  final lines = [
    for (final field in fields.entries)
      if (field.value.trim().isNotEmpty) '${field.key}: ${field.value.trim()}',
  ];
  return '${lines.join('\n')}\n\n${description.trim()}';
}

class EventSubmissionScreen extends StatefulWidget {
  final SubmissionClient client;
  final DateTime Function() clock;

  const EventSubmissionScreen({
    super.key,
    this.client = const HttpSubmissionClient(),
    this.clock = DateTime.now,
  });

  @override
  State<EventSubmissionScreen> createState() => _EventSubmissionScreenState();
}

class _EventSubmissionScreenState extends State<EventSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _dateField = TextEditingController();
  final _time = TextEditingController();
  final _place = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  final _link = TextEditingController();
  final _organizer = TextEditingController();
  final _contact = TextEditingController();
  DateTime? _date;
  bool _sending = false;

  @override
  void dispose() {
    for (final controller in [
      _title,
      _dateField,
      _time,
      _place,
      _price,
      _description,
      _link,
      _organizer,
      _contact,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = widget.clock();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 2, today.month, today.day),
      helpText: 'Fecha del evento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _dateField.text = _dateText(picked);
    });
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    final result = await widget.client.send(
      type: 'evento',
      title: _title.text.trim(),
      description: buildEventDescription(
        date: _date!,
        time: _time.text,
        place: _place.text,
        price: _price.text,
        link: _link.text,
        organizer: _organizer.text,
        description: _description.text,
      ),
      contact: _contact.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);

    final message = switch (result) {
      SubmitResult.ok => '¡Gracias! Hemos recibido tu evento. Lo revisaremos antes de publicarlo.',
      SubmitResult.rateLimited =>
        'Has enviado varios mensajes seguidos. Inténtalo más tarde.',
      SubmitResult.invalid => 'No se pudo enviar. Revisa los datos del evento.',
      SubmitResult.unavailable =>
        'No se pudo enviar. Comprueba tu conexión e inténtalo de nuevo.',
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (result == SubmitResult.ok) navigator.pop();
  }

  InputDecoration _decoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: icon == null ? null : Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
    );
  }

  String? _required(String? value, String message, {int min = 3}) =>
      (value ?? '').trim().length < min ? message : null;

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 2.2,
        fontWeight: FontWeight.w700,
        color: Brand.slate,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 10);
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Envía tu evento')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Organizas algo en Zaragoza? Cuéntanoslo y lo revisaremos '
                  'para publicarlo en la agenda.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Color(0xFF425B71),
                  ),
                ),
                _label('EL EVENTO'),
                TextFormField(
                  controller: _title,
                  enabled: !_sending,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration('Nombre del evento'),
                  validator: (v) =>
                      _required(v, 'Escribe el nombre del evento.'),
                ),
                gap,
                TextFormField(
                  controller: _dateField,
                  enabled: !_sending,
                  readOnly: true,
                  onTap: _pickDate,
                  decoration: _decoration(
                    'Fecha',
                    hint: 'Toca para elegir el día',
                    icon: Icons.calendar_today_outlined,
                  ),
                  validator: (_) =>
                      _date == null ? 'Elige la fecha del evento.' : null,
                ),
                gap,
                gap,
                TextFormField(
                  controller: _time,
                  enabled: !_sending,
                  maxLength: 40,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    'Hora (opcional)',
                    hint: 'Por ejemplo, 19:30',
                    icon: Icons.schedule_outlined,
                  ),
                ),
                gap,
                TextFormField(
                  controller: _place,
                  enabled: !_sending,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    'Lugar',
                    hint: 'Nombre del sitio y dirección',
                    icon: Icons.location_on_outlined,
                  ),
                  validator: (v) => _required(v, 'Indica dónde se celebra.'),
                ),
                gap,
                TextFormField(
                  controller: _price,
                  enabled: !_sending,
                  maxLength: 60,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    'Precio (opcional)',
                    hint: 'Gratis, 10 €…',
                    icon: Icons.confirmation_number_outlined,
                  ),
                ),
                gap,
                TextFormField(
                  controller: _description,
                  enabled: !_sending,
                  maxLength: 1400,
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: _decoration(
                    'Descripción',
                    hint: 'En qué consiste y a quién va dirigido.',
                  ),
                  validator: (v) => _required(
                    v,
                    'Cuéntanos un poco más (mínimo 10 letras).',
                    min: 10,
                  ),
                ),
                gap,
                TextFormField(
                  controller: _link,
                  enabled: !_sending,
                  maxLength: 200,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    'Web o venta de entradas (opcional)',
                    icon: Icons.language_rounded,
                  ),
                ),
                _label('QUIÉN LO ORGANIZA'),
                TextFormField(
                  controller: _organizer,
                  enabled: !_sending,
                  maxLength: 80,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration('Tu nombre o el de la organización'),
                  validator: (v) => _required(v, 'Dinos quién lo organiza.'),
                ),
                gap,
                TextFormField(
                  controller: _contact,
                  enabled: !_sending,
                  maxLength: 200,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _decoration(
                    'Correo o teléfono de contacto',
                    hint: 'Para confirmar los datos contigo',
                  ),
                  validator: (v) => _required(
                    v,
                    'Necesitamos un contacto para confirmar el evento.',
                    min: 6,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tu evento se envía a nuestro servidor y nos llega por '
                  'correo. Lo revisamos antes de publicarlo y usamos tu '
                  'contacto solo para hablar contigo sobre el evento; no se '
                  'muestra en la app.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Brand.slate,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Brand.navy,
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(_sending ? 'Enviando…' : 'Enviar evento'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
