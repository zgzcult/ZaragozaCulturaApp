/// Origen de la información del Ayuntamiento de Zaragoza.
///
/// El aviso legal de la sede electrónica pide citar el origen y mencionar la
/// fecha de la última actualización. Esa línea va al final de la lista de
/// actividades; el resto de condiciones de reutilización están en «Acerca de».
library;

import 'package:flutter/material.dart';

import 'brand.dart';

const String legalNoticeUrl = 'https://www.zaragoza.es/sede/portal/aviso-legal';

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

/// «5 de octubre de 2026».
String longDate(DateTime date) =>
    '${date.day} de ${_months[date.month - 1]} de ${date.year}';

/// Fecha más reciente de una lista de fechas `AAAA-MM-DD`, o null si no hay
/// ninguna válida.
DateTime? latestDate(Iterable<String> isoDates) {
  DateTime? latest;
  for (final text in isoDates) {
    final date = DateTime.tryParse(text);
    if (date != null && (latest == null || date.isAfter(latest))) {
      latest = date;
    }
  }
  return latest;
}

/// Texto del origen de los datos con la fecha de la última actualización.
String originText(DateTime? updated, {String? service}) {
  final from = service == null
      ? 'Ayuntamiento de Zaragoza'
      : 'Ayuntamiento de Zaragoza ($service)';
  final base = 'Origen de los datos: $from';
  return updated == null
      ? '$base.'
      : '$base. Información actualizada por última vez el ${longDate(updated)}.';
}

/// Línea de origen al final de la lista de actividades.
class ReuseNotice extends StatelessWidget {
  /// Última actualización de la información mostrada.
  final DateTime? updated;

  /// Servicio concreto que publica los datos, p. ej. «Servicio de Cultura».
  final String? service;

  const ReuseNotice({super.key, this.updated, this.service});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Brand.line, height: 24),
          Text(
            originText(updated, service: service),
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF738196),
            ),
          ),
        ],
      ),
    );
  }
}
