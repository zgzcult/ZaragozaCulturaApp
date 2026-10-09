/// Lo que la ficha de una actividad enseña después de la descripción:
///  - «Otras fechas»: los demás días en que se repite el mismo acto.
///  - «Sobre el lugar»: dirección, teléfono, autobuses, accesibilidad y cómo
///    llegar, con los datos que publica el Ayuntamiento de cada lugar.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'main.dart';
import 'monuments.dart' show firstPhoneNumber;

// ---------------------------------------------------------------------------
// Otras fechas
// ---------------------------------------------------------------------------

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// «sáb 17 oct».
String shortDayLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

/// Las demás sesiones del mismo acto, de hoy en adelante: una por día, en
/// orden. No incluye el día de la propia ficha.
List<CulturalEvent> otherSessions(
  CulturalEvent event,
  List<CulturalEvent> all,
  DateTime now,
) {
  if (event.sourceId.isEmpty) return const [];
  final today = DateTime(
    now.year,
    now.month,
    now.day,
  ).toIso8601String().split('T').first;
  final byDay = <String, CulturalEvent>{};
  for (final other in all) {
    if (other.sourceId != event.sourceId) continue;
    if (other.date == event.date || other.date.compareTo(today) < 0) continue;
    byDay.putIfAbsent(other.date, () => other);
  }
  final days = byDay.keys.toList()..sort();
  return [for (final day in days) byDay[day]!];
}

// ---------------------------------------------------------------------------
// Datos del lugar
// ---------------------------------------------------------------------------

class VenueInfo {
  final String phone;
  final String transport;
  final String accessibility;

  const VenueInfo({
    this.phone = '',
    this.transport = '',
    this.accessibility = '',
  });

  factory VenueInfo.fromJson(Map<String, dynamic> json) => VenueInfo(
    phone: (json['phone'] ?? '').toString().trim(),
    transport: (json['transport'] ?? '').toString().trim(),
    accessibility: (json['accessibility'] ?? '').toString().trim(),
  );
}

/// {nombre del lugar: sus datos}. Lo que no se entienda se descarta.
Map<String, VenueInfo> parseVenues(Object? decoded) {
  if (decoded is! Map) return const {};
  return {
    for (final entry in decoded.entries)
      if (entry.value is Map)
        entry.key.toString(): VenueInfo.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        ),
  };
}

/// Cómo llegar al lugar de la actividad en Google Maps (enlace gratuito, sin
/// clave): por coordenadas si se conocen y, si no, por nombre y dirección.
Uri eventDirectionsLink(CulturalEvent event) {
  final destination = event.lat != null && event.lng != null
      ? '${event.lat},${event.lng}'
      : [
          event.place,
          event.address,
          'Zaragoza',
        ].where((part) => part.trim().isNotEmpty).join(', ');
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
  });
}

/// Datos de los lugares. Se puede sustituir en los tests.
abstract class VenuesRepository {
  const VenuesRepository();

  Future<Map<String, VenueInfo>> loadCached();

  /// Descarga del servidor; null si no se pudo.
  Future<Map<String, VenueInfo>?> fetchFresh();
}

class HttpVenuesRepository extends VenuesRepository {
  static const _cacheKey = 'cached_venues_json';

  const HttpVenuesRepository();

  @override
  Future<Map<String, VenueInfo>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      return raw == null ? const {} : parseVenues(jsonDecode(raw));
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<Map<String, VenueInfo>?> fetchFresh() async {
    try {
      final response = await http
          .get(Uri.parse('${Brand.serverUrl}/venues'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final venues = parseVenues(jsonDecode(body));
      if (venues.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
      return venues;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Interfaz
// ---------------------------------------------------------------------------

const _sectionTitle = TextStyle(
  fontSize: 19,
  fontWeight: FontWeight.w700,
  color: Brand.navy,
);

/// Bloques de la ficha entre la descripción y la fuente.
class EventExtras extends StatefulWidget {
  final CulturalEvent event;
  final ZaragozaEventsRepository repository;
  final VenuesRepository venues;
  final DateTime Function() clock;

  const EventExtras({
    super.key,
    required this.event,
    this.repository = const ZaragozaEventsRepository(),
    this.venues = const HttpVenuesRepository(),
    this.clock = DateTime.now,
  });

  @override
  State<EventExtras> createState() => _EventExtrasState();
}

class _EventExtrasState extends State<EventExtras> {
  List<CulturalEvent> _sessions = const [];
  VenueInfo _venue = const VenueInfo();
  bool _allDates = false;
  bool _allAccessibility = false;

  static const _maxDates = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final events = await widget.repository.loadCached();
    final cached = await widget.venues.loadCached();
    if (!mounted) return;
    setState(() {
      _sessions = otherSessions(widget.event, events, widget.clock());
      _venue = cached[widget.event.place] ?? _venue;
    });
    if (cached.isNotEmpty) return;
    final fresh = await widget.venues.fetchFresh();
    if (!mounted || fresh == null) return;
    setState(() => _venue = fresh[widget.event.place] ?? _venue);
  }

  Future<void> _launch(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace.')),
    );
  }

  void _openSession(CulturalEvent session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EventLinkScreen(eventId: session.id, repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final shown = _allDates ? _sessions : _sessions.take(_maxDates).toList();
    final hidden = _sessions.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_sessions.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text('Otras fechas', style: _sectionTitle),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final session in shown)
                ActionChip(
                  label: Text(shortDayLabel(DateTime.parse(session.date))),
                  onPressed: () => _openSession(session),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Brand.line),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Brand.navy,
                  ),
                ),
              if (hidden > 0)
                ActionChip(
                  label: Text('+$hidden más'),
                  onPressed: () => setState(() => _allDates = true),
                  backgroundColor: Brand.cream,
                  side: const BorderSide(color: Brand.line),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Brand.skyDeep,
                  ),
                ),
            ],
          ),
        ],
        if (event.place.trim().isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text('Sobre el lugar', style: _sectionTitle),
          const SizedBox(height: 12),
          _venueCard(event),
        ],
      ],
    );
  }

  Widget _venueCard(CulturalEvent event) {
    final phone = firstPhoneNumber(_venue.phone);
    final accessibility = _venue.accessibility;
    final longText = accessibility.length > 170;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.place,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Brand.navy,
            ),
          ),
          if (event.address.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(event.address, style: const TextStyle(color: Brand.slate)),
          ],
          if (phone != null)
            _VenueRow(
              icon: Icons.call_outlined,
              label: 'Teléfono',
              text: _venue.phone,
              onTap: () => _launch(Uri(scheme: 'tel', path: phone)),
            ),
          if (_venue.transport.isNotEmpty)
            _VenueRow(
              icon: Icons.directions_bus_outlined,
              label: 'Autobuses',
              text: _venue.transport,
            ),
          if (accessibility.isNotEmpty)
            _VenueRow(
              icon: Icons.accessible_outlined,
              label: 'Accesibilidad',
              text: accessibility,
              maxLines: longText && !_allAccessibility ? 3 : null,
              action: longText && !_allAccessibility ? 'Ver más' : null,
              onAction: () => setState(() => _allAccessibility = true),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _launch(eventDirectionsLink(event)),
              style: FilledButton.styleFrom(
                backgroundColor: Brand.navy,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.directions_outlined),
              label: const Text('Cómo llegar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VenueRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final int? maxLines;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  const _VenueRow({
    required this.icon,
    required this.label,
    required this.text,
    this.maxLines,
    this.action,
    this.onAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Brand.skyDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Brand.slate,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: maxLines,
                  overflow: maxLines == null ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    height: 1.4,
                    color: onTap == null ? Brand.navy : Brand.skyDeep,
                    fontWeight: onTap == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
                if (action != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: Brand.skyDeep,
                    ),
                    child: Text(action!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
