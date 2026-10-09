import 'dart:convert';

import 'package:add_2_calendar/add_2_calendar.dart' as calendar;
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ads.dart';
import 'crash_reporter.dart';
import 'event_classifier.dart';
import 'event_extras.dart';
import 'event_submission.dart';
import 'home.dart';
import 'legal_notice.dart';
import 'nearby.dart';
import 'notification_settings.dart';
import 'preferences.dart';
import 'reminders.dart';
import 'suggestion.dart';
import 'brand.dart';
import 'ui_kit.dart';

const List<String> _eventsApiUrls = <String>[
  'https://zaragoza-cultura-app.onrender.com/events',
  'http://10.0.2.2:8000/events',
  'http://localhost:8000/events',
  'http://127.0.0.1:8000/events',
];
const String _fallbackAssetPath = 'assets/sample_events.json';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Informes de errores (solo en la versión publicada).
  CrashReporter.install();
  // La licencia de la tipografía (SIL OFL) debe acompañar a la app: aparece en
  // la pantalla de licencias de código abierto.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Montserrat'], text);
  });
  // La app dibuja detrás de las barras del sistema (Android 15 lo impone) y
  // pinta ella misma la franja de los botones de navegación.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ZaragozaCulturaApp());
}

/// Reserva las dos franjas del sistema y las pinta de azul marino con sus
/// iconos en claro: arriba la barra de estado (hora, cobertura, batería) y
/// abajo los botones de navegación de Android. Así siempre se leen, sea cual
/// sea el fondo de la pantalla, y ningún contenido queda debajo de ellas.
class SystemNavigationBarArea extends StatelessWidget {
  final Widget child;

  const SystemNavigationBarArea({super.key, required this.child});

  static const SystemUiOverlayStyle style = SystemUiOverlayStyle(
    // Barra de estado: transparente (se ve nuestra franja) e iconos claros.
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark, // iOS: fondo oscuro, texto claro
    systemStatusBarContrastEnforced: false,
    // Botones de navegación.
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.viewPadding.top;
    final bottom = media.viewPadding.bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: ColoredBox(
        color: Brand.navy,
        child: Column(
          children: [
            SizedBox(height: top),
            Expanded(
              child: MediaQuery(
                data: media
                    .removeViewPadding(removeTop: true, removeBottom: true)
                    .removePadding(removeTop: true, removeBottom: true)
                    .copyWith(
                      // El teclado ya cubre la franja reservada.
                      viewInsets: media.viewInsets.copyWith(
                        bottom: (media.viewInsets.bottom - bottom).clamp(
                          0.0,
                          double.infinity,
                        ),
                      ),
                    ),
                child: child,
              ),
            ),
            SizedBox(height: bottom),
          ],
        ),
      ),
    );
  }
}

String _isoDateKey(DateTime date) {
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().split('T').first;
}

String _longDateLabel(DateTime date) {
  final weekday = <String>[
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ][date.weekday - 1];
  final month = <String>[
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
  ][date.month - 1];
  return '$weekday, ${date.day} de $month';
}

/// Enlace estable para descargar la app. Lo sirve el backend y hoy muestra
/// una página de "próximamente"; al publicar redirigirá a la tienda.
/// Política de privacidad (la sirve el propio backend).
const String _privacyUrl =
    'https://zaragoza-cultura-app.onrender.com/privacidad';

/// Identificador de la app en Google Play. Actualizar si se cambia el
/// applicationId de Android antes de publicar.
const String _androidAppId = 'com.example.zaragoza_cultura_app';

const String _remindersKey = 'reminders_enabled';

String _creditText(dynamic value) {
  if (value is Map) {
    final name = (value['photographer'] ?? '').toString();
    return name.isEmpty ? '' : 'Foto: $name · Pexels';
  }
  return '';
}

String _absoluteImageUrl(String value) {
  if (value.startsWith('//')) {
    return 'https:$value';
  }
  if (value.startsWith('/')) {
    return 'https://www.zaragoza.es$value';
  }
  return value;
}

String _eventDateRange(CulturalEvent event) {
  final start = DateTime.tryParse(event.date);
  final end = DateTime.tryParse(event.endDate);
  if (start == null || end == null || _isoDateKey(start) == _isoDateKey(end)) {
    return start == null ? 'Fecha por confirmar' : _longDateLabel(start);
  }
  return '${_longDateLabel(start)} - ${_longDateLabel(end)}';
}

class CulturalEvent {
  final String id;
  final String title;
  final String description;
  final CulturalCategory category;
  final String date;
  final String time;
  final String place;
  final String address;
  final String officialUrl;
  final String moreInfoUrl;
  final String imageUrl;
  final String endDate;
  final String endTime;

  /// Imagen de reserva (banco de imágenes) y su autoría.
  final String fallbackImageUrl;
  final String imageCredit;

  /// La imagen de la web se comparte entre actos sin relación entre sí.
  final bool genericImage;

  /// Fecha (AAAA-MM-DD) de la última actualización de los datos.
  final String updatedAt;

  /// De dónde viene la actividad: «ayuntamiento» (agenda del Ayuntamiento de
  /// Zaragoza) u otro origen (actividades propias o enviadas por el público).
  final String source;

  /// El Ayuntamiento indica que la entrada es gratuita. Si no publica el
  /// precio no se sabe, y vale false.
  final bool free;

  /// Fechas (AAAA-MM-DD) de comienzo y fin de todo el acto, no solo de este
  /// día. Sirven para saber si es de larga duración (exposiciones...).
  final String runStart;
  final String runEnd;

  /// La actividad no lleva enlace: no se enseña «Más información».
  final bool hideLink;

  /// Código del acto en su origen: el mismo para todas sus fechas.
  final String sourceId;

  /// Coordenadas del lugar (para "Cerca de mí"); null si no se conocen.
  final double? lat;
  final double? lng;

  /// Franjas horarias del mismo acto en el mismo día (p. ej. mañana y tarde).
  final List<String> timeSlots;

  const CulturalEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.date,
    required this.time,
    required this.place,
    this.address = '',
    required this.officialUrl,
    this.moreInfoUrl = '',
    this.imageUrl = '',
    this.endDate = '',
    this.endTime = '',
    this.fallbackImageUrl = '',
    this.imageCredit = '',
    this.genericImage = false,
    this.updatedAt = '',
    this.source = 'ayuntamiento',
    this.free = false,
    this.hideLink = false,
    this.sourceId = '',
    this.runStart = '',
    this.runEnd = '',
    this.lat,
    this.lng,
    this.timeSlots = const <String>[],
  });

  factory CulturalEvent.fromJson(Map<String, dynamic> json) {
    return CulturalEvent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Evento').toString(),
      description: (json['description'] ?? '').toString(),
      category: classifyEvent(
        title: (json['title'] ?? '').toString(),
        place: (json['place'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        sourceCategory: (json['category'] ?? '').toString(),
        time: (json['time'] ?? '').toString(),
        endTime: (json['endTime'] ?? '').toString(),
      ),
      date: (json['date'] ?? _isoDateKey(DateTime.now())).toString(),
      time: (json['time'] ?? '').toString(),
      place: (json['place'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      officialUrl:
          (json['officialUrl'] ??
                  json['official_url'] ??
                  'https://www.zaragoza.es')
              .toString(),
      moreInfoUrl: (json['moreInfoUrl'] ?? json['more_info_url'] ?? '')
          .toString(),
      imageUrl: _absoluteImageUrl((json['imageUrl'] ?? '').toString()),
      endDate: (json['endDate'] ?? '').toString(),
      endTime: (json['endTime'] ?? '').toString(),
      fallbackImageUrl: _absoluteImageUrl(
        (json['fallbackImageUrl'] ?? '').toString(),
      ),
      imageCredit: _creditText(json['imageCredit']),
      genericImage: json['genericImage'] == true,
      updatedAt: (json['lastUpdated'] ?? '').toString().split('T').first,
      source: (json['source'] ?? 'ayuntamiento').toString(),
      free: json['free'] == true,
      hideLink: json['hideLink'] == true,
      sourceId: (json['sourceId'] ?? '').toString(),
      runStart: (json['runStartDate'] ?? '').toString(),
      runEnd: (json['runEndDate'] ?? '').toString(),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }

  /// ¿Es una actividad de la agenda del Ayuntamiento de Zaragoza?
  bool get fromAyuntamiento => source == 'ayuntamiento';

  /// ¿El acto dura más de una semana (exposiciones, ciclos largos...)?
  bool get isLongRunning {
    final start = DateTime.tryParse(runStart);
    final end = DateTime.tryParse(runEnd);
    if (start == null || end == null) return false;
    return end.difference(start).inDays >= _longRunDays;
  }

  CulturalEvent withTimeSlots(
    List<String> slots, {
    String? start,
    String? end,
  }) {
    return CulturalEvent(
      id: id,
      title: title,
      description: description,
      category: category,
      date: date,
      time: time,
      place: place,
      address: address,
      officialUrl: officialUrl,
      moreInfoUrl: moreInfoUrl,
      imageUrl: imageUrl,
      endDate: endDate,
      endTime: endTime,
      fallbackImageUrl: fallbackImageUrl,
      imageCredit: imageCredit,
      genericImage: genericImage,
      updatedAt: updatedAt,
      source: source,
      free: free,
      hideLink: hideLink,
      sourceId: sourceId,
      runStart: start ?? runStart,
      runEnd: end ?? runEnd,
      lat: lat,
      lng: lng,
      timeSlots: slots,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category.name,
      'date': date,
      'time': time,
      'place': place,
      'address': address,
      'officialUrl': officialUrl,
      'moreInfoUrl': moreInfoUrl,
      'imageUrl': imageUrl,
      'endDate': endDate,
      'endTime': endTime,
    };
  }
}

String _timeSlotOf(CulturalEvent event) {
  if (event.time.isEmpty) return '';
  return event.endTime.isEmpty ? event.time : '${event.time}–${event.endTime}';
}

/// Junta las entradas repetidas del mismo acto en el mismo día y lugar
/// (por ejemplo una exposición con horario de mañana y de tarde).
List<CulturalEvent> _mergeSameDay(List<CulturalEvent> events) {
  final merged = <String, CulturalEvent>{};
  final slots = <String, Set<String>>{};
  // Primera y última fecha cargada de cada actividad: sirve de duración
  // aproximada cuando el servidor no envía las fechas reales del acto.
  final firstDate = <String, String>{};
  final lastDate = <String, String>{};
  for (final event in events) {
    final key = '${event.title}|${event.place}|${event.date}';
    final activity = '${event.title}|${event.place}';
    final slot = _timeSlotOf(event);
    merged.putIfAbsent(key, () => event);
    final set = slots.putIfAbsent(key, () => <String>{});
    if (slot.isNotEmpty) set.add(slot);
    final first = firstDate[activity];
    if (first == null || event.date.compareTo(first) < 0) {
      firstDate[activity] = event.date;
    }
    final last = lastDate[activity];
    if (last == null || event.date.compareTo(last) > 0) {
      lastDate[activity] = event.date;
    }
  }
  return merged.entries.map((entry) {
    final event = entry.value;
    final list = slots[entry.key]!.toList()..sort();
    final activity = '${event.title}|${event.place}';
    return event.withTimeSlots(
      list,
      start: event.runStart.isEmpty ? firstDate[activity] : null,
      end: event.runEnd.isEmpty ? lastDate[activity] : null,
    );
  }).toList();
}

/// Una actividad que dura más de este número de días se considera de larga
/// duración y se muestra después de las demás.
const int _longRunDays = 7;

/// Orden de las actividades de un mismo día: primero las de pocos días (con
/// hora, por orden de hora; luego las que no tienen hora) y al final las de
/// larga duración, como las exposiciones.
int compareEventsWithinDay(CulturalEvent a, CulturalEvent b) {
  if (a.isLongRunning != b.isLongRunning) {
    return a.isLongRunning ? 1 : -1;
  }
  final timeA = a.timeSlots.isEmpty ? null : a.timeSlots.first;
  final timeB = b.timeSlots.isEmpty ? null : b.timeSlots.first;
  if (timeA != null && timeB != null) {
    final byTime = timeA.compareTo(timeB);
    if (byTime != 0) return byTime;
  } else if (timeA != null) {
    return -1;
  } else if (timeB != null) {
    return 1;
  }
  return a.title.compareTo(b.title);
}

/// Una actividad encontrada por la búsqueda: su fecha más próxima y cuántas
/// fechas más tiene.
class SearchResult {
  final CulturalEvent event;
  final int otherDates;

  const SearchResult({required this.event, required this.otherDates});
}

class _SearchText {
  final String title;
  final String near;
  final String all;

  const _SearchText(this.title, this.near, this.all);
}

final Expando<_SearchText> _searchTextCache = Expando<_SearchText>();

_SearchText _searchTextOf(CulturalEvent event) {
  return _searchTextCache[event] ??= () {
    final title = normalizeForSearch(event.title);
    final near =
        '$title ${normalizeForSearch(event.place)} '
        '${normalizeForSearch(_categoryLabel(event.category))}';
    final description = event.description.length > 600
        ? event.description.substring(0, 600)
        : event.description;
    return _SearchText(title, near, '$near ${normalizeForSearch(description)}');
  }();
}

/// Busca actividades que contengan todas las palabras de [query] (sin
/// distinguir mayúsculas ni tildes) en el título, el lugar, la categoría o la
/// descripción. Una actividad con muchas fechas aparece una sola vez, con su
/// fecha más próxima desde [today]. Primero salen las que coinciden en el
/// título.
List<SearchResult> searchEvents(
  List<CulturalEvent> events,
  String query, {
  required DateTime today,
}) {
  final terms = normalizeForSearch(query)
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  if (terms.isEmpty) return const <SearchResult>[];

  final todayKey = _isoDateKey(today);
  final groups = <String, List<CulturalEvent>>{};
  for (final event in events) {
    if (event.date.compareTo(todayKey) < 0) continue;
    final key =
        '${normalizeForSearch(event.title)}|'
        '${normalizeForSearch(event.place)}';
    groups.putIfAbsent(key, () => <CulturalEvent>[]).add(event);
  }

  final scored = <({int score, SearchResult result})>[];
  for (final group in groups.values) {
    group.sort((a, b) => a.date.compareTo(b.date));
    final first = group.first;
    final text = _searchTextOf(first);
    final int score;
    if (terms.every(text.title.contains)) {
      score = 0;
    } else if (terms.every(text.near.contains)) {
      score = 1;
    } else if (terms.every(text.all.contains)) {
      score = 2;
    } else {
      continue;
    }
    final dates = group.map((event) => event.date).toSet();
    scored.add((
      score: score,
      result: SearchResult(event: first, otherDates: dates.length - 1),
    ));
  }

  scored.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    if (byScore != 0) return byScore;
    // A igual relevancia, primero las actividades de pocos días.
    final longA = a.result.event.isLongRunning;
    final longB = b.result.event.isLongRunning;
    if (longA != longB) return longA ? 1 : -1;
    final byDate = a.result.event.date.compareTo(b.result.event.date);
    return byDate != 0
        ? byDate
        : a.result.event.title.compareTo(b.result.event.title);
  });
  return [for (final item in scored) item.result];
}

/// Enlace de «Más información». Si la actividad apunta a una página general
/// del portal (zaragoza.es/sede/portal...), no se usa: se abre la ficha de la
/// actividad en la agenda de cultura, donde la encontró el scraper.
String moreInfoTarget(CulturalEvent event) {
  final url = event.moreInfoUrl.trim();
  final uri = Uri.tryParse(url);
  final isPortal =
      uri != null &&
      uri.host.toLowerCase().endsWith('zaragoza.es') &&
      uri.path.toLowerCase().startsWith('/sede/portal');
  return url.isEmpty || isPortal ? event.officialUrl : url;
}

/// Texto para compartir una actividad (mensajería, redes...).
/// Enlace de una actividad en nuestra app: abre su página y, desde ella, la
/// ficha dentro de la aplicación.
String eventShareUrl(CulturalEvent event) =>
    '${Brand.serverUrl}/app/evento/${event.id}';

/// Texto que se comparte: los datos de la actividad y, como único enlace, el
/// de la actividad en nuestra app.
String buildShareText(CulturalEvent event) {
  final date = DateTime.tryParse(event.date);
  final time = _eventTimeLabel(event);
  var summary = event.description.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (summary.length > 180) {
    summary = '${summary.substring(0, 180).trimRight()}…';
  }
  return [
    event.title,
    if (date != null) _longDateLabel(date),
    if (time.isNotEmpty) time,
    if (event.place.isNotEmpty) event.place,
    if (summary.isNotEmpty) ...['', summary],
    '',
    'Míralo en ${Brand.name}: ${eventShareUrl(event)}',
  ].join('\n');
}

/// Comienzo y fin de una actividad para el calendario. Usa la primera franja
/// horaria; si no hay horario, será un evento de todo el día.
({DateTime start, DateTime end, bool allDay}) calendarWindowFor(
  CulturalEvent event,
) {
  final day = DateTime.tryParse(event.date) ?? DateTime.now();
  final base = DateTime(day.year, day.month, day.day);
  final slot = event.timeSlots.isEmpty ? '' : event.timeSlots.first;
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?:\s*[–-]\s*(\d{1,2}):(\d{2}))?')
      .firstMatch(slot);
  if (match == null) {
    return (start: base, end: base.add(const Duration(days: 1)), allDay: true);
  }
  final start = base.add(
    Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
    ),
  );
  var end = match.group(3) == null
      ? start.add(const Duration(hours: 1))
      : base.add(
          Duration(
            hours: int.parse(match.group(3)!),
            minutes: int.parse(match.group(4)!),
          ),
        );
  if (!end.isAfter(start)) {
    end = start.add(const Duration(hours: 1));
  }
  return (start: start, end: end, allDay: false);
}

/// Texto del horario para mostrar al usuario.
String _eventTimeLabel(CulturalEvent event) {
  if (event.timeSlots.isEmpty) return '';
  final text = event.timeSlots.join(' · ');
  return event.category == CulturalCategory.exposiciones
      ? 'Abierto $text'
      : text;
}

List<CulturalEvent> _parseEventList(dynamic decoded) {
  final items = decoded is List
      ? decoded
      : (decoded is Map ? decoded['events'] ?? [] : <dynamic>[]);

  if (items is! List) {
    return const <CulturalEvent>[];
  }

  return _mergeSameDay(
    items
        .map(
          (item) =>
              CulturalEvent.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );
}

List<CulturalEvent> buildFallbackEvents() {
  final today = DateTime.now();
  return [
    CulturalEvent(
      id: 'musica-1',
      title: 'Jazz en el Patio',
      description: 'Noche de jazz con artistas locales y una programación de música íntima en el centro histórico.',
      category: CulturalCategory.musica,
      date: _isoDateKey(today),
      time: '20:30',
      timeSlots: const ['20:30'],
      place: 'Patio de la Infanta',
      officialUrl: 'https://www.zaragoza.es',
    ),
    CulturalEvent(
      id: 'teatro-1',
      title: 'Obra de Teatro Clásico',
      description: 'Versión moderna de una obra teatral clásica con reparto local y puesta en escena contemporánea.',
      category: CulturalCategory.teatro,
      date: _isoDateKey(today.add(const Duration(days: 1))),
      time: '19:00',
      timeSlots: const ['19:00'],
      place: 'Teatro Principal',
      officialUrl: 'https://www.zaragoza.es',
    ),
    CulturalEvent(
      id: 'gastronomia-1',
      title: 'Ruta de Tapas del Barrio',
      description: 'Recorrido gastronómico para descubrir sabores locales, vinos y platos tradicionales de la ciudad.',
      category: CulturalCategory.gastronomia,
      date: _isoDateKey(today.add(const Duration(days: 2))),
      time: '18:30',
      timeSlots: const ['18:30'],
      place: 'Centro de Zaragoza',
      officialUrl: 'https://www.zaragoza.es',
    ),
    CulturalEvent(
      id: 'eventos-1',
      title: 'Feria de Artesanía',
      description: 'Encuentro con creadores locales, talleres y puestos de artesanía y cultura popular.',
      category: CulturalCategory.eventos,
      date: _isoDateKey(today.add(const Duration(days: 3))),
      time: '11:00',
      timeSlots: const ['11:00'],
      place: 'Plaza del Pilar',
      officialUrl: 'https://www.zaragoza.es',
    ),
  ];
}

class ZaragozaEventsRepository {
  static const String _cacheKey = 'cached_events_json';
  static const String _cacheTimeKey = 'cached_events_time';

  final List<String> apiUrls;
  final String fallbackAssetPath;

  const ZaragozaEventsRepository({
    this.apiUrls = _eventsApiUrls,
    this.fallbackAssetPath = _fallbackAssetPath,
  });

  /// Eventos guardados en el teléfono en la última descarga correcta.
  Future<List<CulturalEvent>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) {
        return const <CulturalEvent>[];
      }
      return _parseEventList(jsonDecode(raw));
    } catch (_) {
      return const <CulturalEvent>[];
    }
  }

  /// Descarga eventos del servidor. Devuelve null si no se pudo.
  /// El primer servidor (Render) puede tardar en despertar; el resto son
  /// servidores locales de desarrollo y se descartan rápido.
  Future<List<CulturalEvent>?> fetchFresh() async {
    for (var i = 0; i < apiUrls.length; i++) {
      try {
        final response = await http
            .get(Uri.parse(apiUrls[i]))
            .timeout(Duration(seconds: i == 0 ? 60 : 3));

        debugPrint(
          'EVENTS ${apiUrls[i]} -> HTTP ${response.statusCode}, ${response.bodyBytes.length} bytes',
        );
        if (response.statusCode == 200) {
          final body = utf8.decode(response.bodyBytes);
          final parsed = _parseEventList(jsonDecode(body));
          if (parsed.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cacheKey, body);
            await prefs.setString(
              _cacheTimeKey,
              DateTime.now().toIso8601String(),
            );
            return parsed;
          }
        }
      } catch (error) {
        debugPrint('EVENTS ${apiUrls[i]} ERROR: $error');
      }
    }
    return null;
  }

  /// Datos de emergencia incluidos en la app.
  Future<List<CulturalEvent>> loadFallback() async {
    try {
      final content = await rootBundle.loadString(fallbackAssetPath);
      final parsed = _parseEventList(jsonDecode(content));
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } catch (_) {}

    return buildFallbackEvents();
  }
}

Route<void> _opensNothing(RouteSettings settings) => PageRouteBuilder<void>(
  settings: settings,
  opaque: false,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (_, _, _) => const _ClosesItself(),
);

/// Página vacía que se cierra sola: es lo que se abre con un enlace que no
/// corresponde a ninguna actividad, para que solo se vea la app.
class _ClosesItself extends StatefulWidget {
  const _ClosesItself();

  @override
  State<_ClosesItself> createState() => _ClosesItselfState();
}

class _ClosesItselfState extends State<_ClosesItself> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Identificador de la actividad de un enlace («/evento/ID» o
/// «/app/evento/ID»), o null si la ruta no es de una actividad.
String? eventIdFromRoute(String? route) {
  final match = RegExp(r'^/(?:app/)?evento/([0-9a-fA-F]{8,64})/?$')
      .firstMatch(Uri.tryParse(route ?? '')?.path ?? '');
  return match?.group(1)?.toLowerCase();
}

/// Guarda o quita un favorito y, si los avisos están activados, los
/// reprograma. Devuelve los favoritos resultantes.
Future<Set<String>> toggleStoredFavorite(
  String eventId, {
  ZaragozaEventsRepository repository = const ZaragozaEventsRepository(),
}) async {
  final storage = FavoritesStorage();
  final favorites = await storage.load();
  if (!favorites.remove(eventId)) favorites.add(eventId);
  await storage.save(favorites);
  if (await loadRemindersEnabled()) {
    await setFavoriteReminders(true, repository: repository);
  }
  return favorites;
}

/// Abre la ficha de una actividad a partir de su identificador: al pulsar un
/// aviso de favoritos o un enlace compartido.
class EventLinkScreen extends StatefulWidget {
  final String eventId;
  final ZaragozaEventsRepository repository;

  const EventLinkScreen({
    super.key,
    required this.eventId,
    this.repository = const ZaragozaEventsRepository(),
  });

  @override
  State<EventLinkScreen> createState() => _EventLinkScreenState();
}

class _EventLinkScreenState extends State<EventLinkScreen> {
  CulturalEvent? _event;
  bool _loading = true;
  bool _favorite = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  CulturalEvent? _find(List<CulturalEvent> events) {
    for (final event in events) {
      if (event.id == widget.eventId) return event;
    }
    return null;
  }

  Future<void> _load() async {
    final favorites = await FavoritesStorage().load();
    // Primero lo guardado en el teléfono; si no está, se descarga.
    var event = _find(await widget.repository.loadCached());
    event ??= _find(await widget.repository.fetchFresh() ?? const []);
    if (!mounted) return;
    setState(() {
      _event = event;
      _favorite = favorites.contains(widget.eventId);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    if (event != null) {
      return EventDetailScreen(
        event: event,
        isFavorite: _favorite,
        onToggleFavorite: () =>
            toggleStoredFavorite(event.id, repository: widget.repository),
      );
    }
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Actividad')),
      body: _loading
          ? const SkeletonList(count: 1)
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_busy_outlined,
                      size: 48,
                      color: Color(0xFF9AA8B8),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Esta actividad ya no está en la agenda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Brand.slate, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AgendaScreen(repository: widget.repository),
                        ),
                      ),
                      child: const Text('Ver la agenda'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// ¿Están activados los avisos de favoritos?
Future<bool> loadRemindersEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_remindersKey) ?? false;
}

/// Activa o desactiva los avisos de favoritos desde Ajustes. Al activar pide
/// el permiso de notificaciones y programa los avisos con los favoritos y la
/// agenda guardados en el teléfono. Devuelve si el cambio se pudo hacer.
Future<bool> setFavoriteReminders(
  bool enabled, {
  ZaragozaEventsRepository repository = const ZaragozaEventsRepository(),
  ReminderService? service,
}) async {
  final reminders = service ?? ReminderService();
  if (enabled && !await reminders.requestPermission()) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_remindersKey, enabled);
  if (!enabled) {
    await reminders.cancelAll();
    return true;
  }
  final favorites = await FavoritesStorage().load();
  final events = await repository.loadCached();
  final candidates = [
    for (final e in events)
      if (favorites.contains(e.id))
        ReminderCandidate(
          eventId: e.id,
          title: e.title,
          date: e.date,
          timeLabel: _eventTimeLabel(e),
          place: e.place,
        ),
  ];
  await reminders.sync(planReminders(candidates, now: DateTime.now()));
  return true;
}

class FavoritesStorage {
  static const String _favoritesKey = 'favorite_event_ids';

  Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_favoritesKey) ?? const <String>[];
    return saved.toSet();
  }

  Future<void> save(Set<String> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, favorites.toList());
  }
}

class ZaragozaCulturaApp extends StatelessWidget {
  final ZaragozaEventsRepository repository;
  final LocationService locationService;

  /// Para abrir pantallas desde fuera del árbol (lo usan los tests).
  final GlobalKey<NavigatorState>? navigatorKey;

  const ZaragozaCulturaApp({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.locationService = const DeviceLocationService(),
    this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Brand.navy,
          brightness: Brightness.light,
        ).copyWith(
          primary: Brand.navy,
          onPrimary: Colors.white,
          secondary: Brand.coral,
          onSecondary: Brand.navy,
          tertiary: Brand.sky,
          onTertiary: Brand.navy,
          surface: Colors.white,
          surfaceTint: Colors.transparent,
        );
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: Brand.fontFamily,
        scaffoldBackgroundColor: Brand.cream,
        colorScheme: scheme,
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Brand.navy,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: Brand.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Brand.skyTint,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: Brand.navy,
            ),
          ),
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: Brand.navy),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Brand.coral,
          foregroundColor: Brand.navy,
        ),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Brand.coral : null,
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : null,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Brand.navy,
          contentTextStyle: TextStyle(
            fontFamily: Brand.fontFamily,
            color: Colors.white,
          ),
        ),
      ),
      builder: (context, child) => SystemNavigationBarArea(child: child!),
      // Un enlace compartido (o el botón de su página web) abre la ficha de
      // la actividad dentro de la app.
      onGenerateRoute: (settings) {
        final eventId = eventIdFromRoute(settings.name);
        if (eventId == null) {
          // «/inicio» (enlace genérico) solo abre la app.
          return settings.name == '/inicio' ? _opensNothing(settings) : null;
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              EventLinkScreen(eventId: eventId, repository: repository),
        );
      },
      // Cualquier otro enlace solo abre la app: no añade ninguna pantalla.
      onUnknownRoute: _opensNothing,
      home: HomeScreen(
        repository: repository,
        locationService: locationService,
      ),
    );
  }
}

class AgendaScreen extends StatefulWidget {
  final ZaragozaEventsRepository repository;
  final LocationService locationService;

  const AgendaScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.locationService = const DeviceLocationService(),
  });

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  ZaragozaEventsRepository get _repository => widget.repository;
  final FavoritesStorage _favoritesStorage = FavoritesStorage();
  final Set<String> _favoriteEventIds = <String>{};

  final List<DateTime> _calendarDays = List<DateTime>.generate(45, (index) {
    final date = DateTime.now().add(Duration(days: index));
    return DateTime(date.year, date.month, date.day);
  });

  DateTime selectedDate = DateTime.now();
  CulturalCategory selectedCategory = CulturalCategory.all;
  bool favoritesOnly = false;

  /// Categorías que el usuario prefiere, por prioridad («Mis preferencias»).
  List<CulturalCategory> _preferredCategories = const [];

  /// Filtros de la agenda: «Todos» y después las categorías, primero las
  /// preferidas.
  List<CulturalCategory> get _filterCategories => [
    CulturalCategory.all,
    ...categoriesByPreference(_preferredCategories),
  ];
  List<CulturalEvent> _events = <CulturalEvent>[];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _loadFailed = false;
  bool _remindersEnabled = false;
  final ReminderService _reminderService = ReminderService();

  bool searchMode = false;
  bool nearbyMode = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Pantalla de búsqueda: una actividad, una vez, con su fecha más próxima.
  Widget _buildSearchBody() {
    final results = searchEvents(_events, _query, today: DateTime.now());
    final hasQuery = _query.trim().isNotEmpty;

    Widget message(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Brand.slate, height: 1.4),
        ),
      ),
    );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Text(
              'Buscar',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Brand.navy,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Nombre, lugar o categoría',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Brand.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Brand.line),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: !hasQuery
                ? message(
                    'Escribe lo que buscas: un nombre, un lugar o una '
                    'categoría (por ejemplo «jazz» o «Museo de Goya»).',
                  )
                : results.isEmpty
                ? message('No hay actividades que coincidan con «$_query».')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final result = results[index];
                      final extra = result.otherDates == 0
                          ? ''
                          : result.otherDates == 1
                          ? ' · y 1 fecha más'
                          : ' · y ${result.otherDates} fechas más';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              'Próxima fecha: ${_dayHeader(result.event.date)}$extra',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Brand.navy,
                              ),
                            ),
                          ),
                          _eventCard(result.event),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Reprograma los avisos con los favoritos actuales (si están activados).
  Future<void> _syncReminders() async {
    if (!_remindersEnabled) return;
    final candidates = _events
        .where((e) => _favoriteEventIds.contains(e.id))
        .map(
          (e) => ReminderCandidate(
            eventId: e.id,
            title: e.title,
            date: e.date,
            timeLabel: _eventTimeLabel(e),
            place: e.place,
          ),
        )
        .toList();
    await _reminderService.sync(planReminders(candidates, now: DateTime.now()));
  }

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
    _loadData();
  }

  /// Muestra al instante lo guardado en el teléfono y actualiza en segundo
  /// plano con lo último del servidor.
  Future<void> _loadData() async {
    if (_isRefreshing) {
      return;
    }
    setState(() {
      _isRefreshing = true;
      _loadFailed = false;
    });

    final favorites = await _favoritesStorage.load();
    final cached = await _repository.loadCached();
    final preferred = await CategoryPreferences.load();
    final prefs = await SharedPreferences.getInstance();
    _remindersEnabled = prefs.getBool(_remindersKey) ?? false;
    if (!mounted) {
      return;
    }
    setState(() {
      _preferredCategories = preferred;
      _favoriteEventIds
        ..clear()
        ..addAll(favorites);
      if (cached.isNotEmpty) {
        _events = cached;
        _isLoading = false;
      }
    });

    final fresh = await _repository.fetchFresh();
    if (!mounted) {
      return;
    }

    if (fresh == null && _events.isEmpty) {
      final fallback = await _repository.loadFallback();
      if (!mounted) {
        return;
      }
      setState(() {
        _events = fallback;
        _loadFailed = true;
        _isLoading = false;
        _isRefreshing = false;
      });
      return;
    }

    setState(() {
      if (fresh != null) {
        _events = fresh;
      }
      _loadFailed = fresh == null;
      _isLoading = false;
      _isRefreshing = false;
    });
    await _syncReminders();
  }

  List<CulturalEvent> get filteredEvents {
    final dateKey = _isoDateKey(selectedDate);
    var byDate = _events.where((event) => event.date == dateKey).toList();

    if (selectedCategory != CulturalCategory.all) {
      byDate = byDate
          .where((event) => event.category == selectedCategory)
          .toList();
    }

    if (favoritesOnly) {
      byDate = byDate
          .where((event) => _favoriteEventIds.contains(event.id))
          .toList();
    }

    byDate.sort(compareEventsWithinDay);
    return byDate;
  }

  Future<void> toggleFavorite(String eventId) async {
    setState(() {
      if (_favoriteEventIds.contains(eventId)) {
        _favoriteEventIds.remove(eventId);
      } else {
        _favoriteEventIds.add(eventId);
      }
    });

    await _favoritesStorage.save(_favoriteEventIds);
    await _syncReminders();
  }

  void _openEvent(CulturalEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          isFavorite: _favoriteEventIds.contains(event.id),
          onToggleFavorite: () => toggleFavorite(event.id),
        ),
      ),
    );
  }

  Widget _eventCard(CulturalEvent event) {
    return EventCard(
      event: event,
      isFavorite: _favoriteEventIds.contains(event.id),
      onFavorite: () => toggleFavorite(event.id),
      onOpen: () => _openEvent(event),
    );
  }

  String _dayHeader(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    final today = DateTime.now();
    final diff = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    final label = _longDateLabel(date);
    if (diff == 0) return 'Hoy · $label';
    if (diff == 1) return 'Mañana · $label';
    return label;
  }

  /// Todos los favoritos desde hoy, agrupados por día y ordenados del más
  /// próximo al más lejano.
  List<Widget> _favoriteSlivers() {
    final todayKey = _isoDateKey(DateTime.now());
    final favorites =
        _events
            .where(
              (e) =>
                  _favoriteEventIds.contains(e.id) &&
                  e.date.compareTo(todayKey) >= 0,
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            return byDate != 0 ? byDate : compareEventsWithinDay(a, b);
          });

    if (favorites.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 48,
                    color: Color(0xFF9AA8B8),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Aún no tienes favoritos.\n'
                    'Pulsa el corazón de una actividad para guardarla aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.slate, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final items = <Object>[];
    String? lastDate;
    for (final event in favorites) {
      if (event.date != lastDate) {
        items.add(event.date);
        lastDate = event.date;
      }
      items.add(event);
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = items[index];
            if (item is String) {
              return Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 10),
                child: Text(
                  _dayHeader(item),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Brand.navy,
                  ),
                ),
              );
            }
            return _eventCard(item as CulturalEvent);
          }, childCount: items.length),
        ),
      ),
    ];
  }

  /// Origen de la información del Ayuntamiento, al final de la lista de
  /// actividades del día (no en Favoritos).
  Widget _reuseNoticeSliver() => SliverToBoxAdapter(
    child: ReuseNotice(
      service: 'Servicio de Cultura',
      updated: latestDate(_events.map((e) => e.updatedAt)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      bottomNavigationBar: NavigationBar(
        // Ajustes está en la pantalla principal: son ajustes de toda la app.
        selectedIndex: nearbyMode
            ? 1
            : searchMode
            ? 2
            : (favoritesOnly ? 3 : 0),
        onDestinationSelected: (index) {
          if (index == 0) {
            setState(() {
              favoritesOnly = false;
              searchMode = false;
              nearbyMode = false;
            });
          } else if (index == 1) {
            setState(() {
              favoritesOnly = false;
              searchMode = false;
              nearbyMode = true;
            });
          } else if (index == 2) {
            setState(() {
              favoritesOnly = false;
              searchMode = true;
              nearbyMode = false;
            });
          } else if (index == 3) {
            setState(() {
              favoritesOnly = !favoritesOnly || searchMode || nearbyMode;
              searchMode = false;
              nearbyMode = false;
            });
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.near_me_outlined),
            selectedIcon: Icon(Icons.near_me),
            label: 'Cerca de mí',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favoritos',
          ),
        ],
      ),
      body: _isLoading
          ? const SafeArea(child: SkeletonList())
          : nearbyMode
          ? NearbyScreen(
              events: _events,
              locationService: widget.locationService,
              dayLabel: _dayHeader,
              timeLabel: _eventTimeLabel,
              onOpen: _openEvent,
            )
          : searchMode
          ? _buildSearchBody()
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (Navigator.canPop(context))
                                  IconButton(
                                    tooltip: 'Inicio',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        Navigator.maybePop(context),
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                Expanded(
                                  child: Text(
                                    favoritesOnly
                                        ? 'Tus favoritos'
                                        : 'Actividades',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: Brand.navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              favoritesOnly
                                  ? 'Ordenados por fecha, del más próximo al más lejano'
                                  : 'Zaragoza · ${_monthLabel(selectedDate)}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Brand.slate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isRefreshing || _loadFailed)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: _isRefreshing
                              ? const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LinearProgressIndicator(minHeight: 3),
                                    SizedBox(height: 6),
                                    Text(
                                      'Actualizando actividades…',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Brand.slate,
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    const Icon(
                                      Icons.cloud_off,
                                      size: 18,
                                      color: Brand.slate,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'No se pudo actualizar. Mostrando datos guardados.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Brand.slate,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _loadData,
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    if (favoritesOnly)
                      ..._favoriteSlivers()
                    else ...[
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _DateStripDelegate(
                          dates: _calendarDays,
                          selectedDate: selectedDate,
                          onSelected: (date) =>
                              setState(() => selectedDate = date),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 58,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                            scrollDirection: Axis.horizontal,
                            itemCount: _filterCategories.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final category = _filterCategories[index];
                              return ChoiceChip(
                                label: Text(_categoryLabel(category)),
                                selected: selectedCategory == category,
                                onSelected: (_) =>
                                    setState(() => selectedCategory = category),
                                selectedColor: Brand.navy,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: selectedCategory == category
                                      ? Colors.white
                                      : const Color(0xFF1D2939),
                                  fontWeight: FontWeight.w700,
                                ),
                                side: const BorderSide(color: Brand.line),
                              );
                            },
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _longDateLabel(selectedDate),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Brand.navy,
                                  ),
                                ),
                              ),
                              Text(
                                '${filteredEvents.length} actividades',
                                style: const TextStyle(
                                  color: Brand.slate,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (filteredEvents.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'No hay actividades para este día.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Brand.slate),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              if (isAdIndex(index)) {
                                return const AdSlot();
                              }
                              final event =
                                  filteredEvents[eventIndexFor(index)];
                              final isFavorite = _favoriteEventIds.contains(
                                event.id,
                              );
                              return EventCard(
                                event: event,
                                isFavorite: isFavorite,
                                onFavorite: () => toggleFavorite(event.id),
                                onOpen: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => EventDetailScreen(
                                      event: event,
                                      isFavorite: isFavorite,
                                      onToggleFavorite: () =>
                                          toggleFavorite(event.id),
                                    ),
                                  ),
                                ),
                              );
                            }, childCount: withAds(filteredEvents.length)),
                          ),
                        ),
                      if (filteredEvents.isNotEmpty) _reuseNoticeSliver(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

String _monthLabel(DateTime date) {
  return <String>[
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
      ][date.month - 1].replaceFirstMapped(
        RegExp(r'^.'),
        (match) => match.group(0)!.toUpperCase(),
      ) +
      ' ${date.year}';
}

class _DateStripDelegate extends SliverPersistentHeaderDelegate {
  final List<DateTime> dates;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;

  const _DateStripDelegate({
    required this.dates,
    required this.selectedDate,
    required this.onSelected,
  });

  @override
  double get minExtent => 62;

  @override
  double get maxExtent => 80;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final todayKey = _isoDateKey(DateTime.now());
    return Container(
      color: Brand.cream,
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final date = dates[index];
          final key = _isoDateKey(date);
          final selected = key == _isoDateKey(selectedDate);
          final isToday = key == todayKey;
          final dim = selected ? Colors.white70 : Brand.slate;
          return Semantics(
            button: true,
            selected: selected,
            label: _longDateLabel(date),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onSelected(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 46,
                decoration: BoxDecoration(
                  color: selected ? Brand.navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _weekdayShort(date),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: dim,
                      ),
                    ),
                    SizedBox(height: 4 - progress * 2),
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 18 - progress * 2,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : Brand.navy,
                      ),
                    ),
                    SizedBox(height: 5 - progress * 2),
                    // Punto coral para «hoy».
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isToday ? Brand.coral : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DateStripDelegate oldDelegate) =>
      oldDelegate.selectedDate != selectedDate || oldDelegate.dates != dates;
}

String _weekdayShort(DateTime date) {
  return <String>[
    'LUN',
    'MAR',
    'MIÉ',
    'JUE',
    'VIE',
    'SÁB',
    'DOM',
  ][date.weekday - 1];
}

/// Etiqueta de la imagen compartida entre la tarjeta y la ficha (transición
/// Hero). La tarjeta la deja preparada justo antes de abrir la ficha y la
/// ficha la recoge al crearse; así cada tarjeta tiene la suya aunque una
/// actividad aparezca varias veces.
class EventHeroTag {
  const EventHeroTag._();

  static Object? _pending;

  static void _prepare(Object tag) {
    _pending = tag;
    WidgetsBinding.instance.addPostFrameCallback((_) => _pending = null);
  }

  static Object? _take() {
    final tag = _pending;
    _pending = null;
    return tag;
  }
}

const List<String> _monthShort = <String>[
  'ENE',
  'FEB',
  'MAR',
  'ABR',
  'MAY',
  'JUN',
  'JUL',
  'AGO',
  'SEP',
  'OCT',
  'NOV',
  'DIC',
];

class EventCard extends StatefulWidget {
  final CulturalEvent event;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  const EventCard({
    super.key,
    required this.event,
    required this.isFavorite,
    required this.onFavorite,
    required this.onOpen,
  });

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  final Object _heroTag = Object();

  void _open() {
    EventHeroTag._prepare(_heroTag);
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final date = DateTime.tryParse(event.date);
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B2D4A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 210,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: _heroTag,
                    child: _EventImage(event: event),
                  ),
                  // Degradado para que el título se lea sobre cualquier foto.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.35, 1.0],
                        colors: [
                          Color(0x330B2D4A),
                          Color(0x000B2D4A),
                          Color(0xE60B2D4A),
                        ],
                      ),
                    ),
                  ),
                  if (date != null)
                    Positioned(top: 12, left: 12, child: _DateTag(date: date)),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: FavoriteHeart(
                      isFavorite: widget.isFavorite,
                      onPressed: widget.onFavorite,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CategoryPill(category: event.category),
                        const SizedBox(height: 8),
                        Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Color(0x660B2D4A), blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.timeSlots.isNotEmpty) ...[
                    _InfoRow(
                      icon: Icons.access_time_rounded,
                      text: _eventTimeLabel(event),
                    ),
                    const SizedBox(height: 6),
                  ],
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: event.place.isEmpty
                        ? 'Lugar por confirmar'
                        : event.place,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fecha en una pequeña etiqueta blanca: día grande y mes abreviado.
class _DateTag extends StatelessWidget {
  final DateTime date;

  const _DateTag({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.day}',
            style: const TextStyle(
              fontSize: 20,
              height: 1.0,
              fontWeight: FontWeight.w700,
              color: Brand.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _monthShort[date.month - 1],
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Brand.coralDeep,
            ),
          ),
        ],
      ),
    );
  }
}

/// Píldora blanca con el nombre de la categoría en su color.
class _CategoryPill extends StatelessWidget {
  final CulturalCategory category;

  const _CategoryPill({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _categoryIcon(category),
            size: 14,
            color: _categoryColor(category),
          ),
          const SizedBox(width: 5),
          Text(
            _categoryLabel(category),
            style: TextStyle(
              color: _categoryColor(category),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _categoryIcon(CulturalCategory category) {
  switch (category) {
    case CulturalCategory.musica:
      return Icons.music_note;
    case CulturalCategory.teatro:
      return Icons.theater_comedy;
    case CulturalCategory.exposiciones:
      return Icons.museum_outlined;
    case CulturalCategory.gastronomia:
      return Icons.restaurant;
    case CulturalCategory.cine:
      return Icons.movie_outlined;
    case CulturalCategory.charlas:
      return Icons.record_voice_over;
    case CulturalCategory.eventos:
      return Icons.event;
    case CulturalCategory.all:
      return Icons.auto_awesome;
  }
}

class EventDetailScreen extends StatefulWidget {
  final CulturalEvent event;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  /// De dónde salen las otras fechas del acto y los datos del lugar.
  final ZaragozaEventsRepository repository;
  final VenuesRepository venues;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.repository = const ZaragozaEventsRepository(),
    this.venues = const HttpVenuesRepository(),
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late bool isFavorite = widget.isFavorite;
  final ScrollController _scroll = ScrollController();
  Object? _heroTag;
  bool _collapsed = false;

  CulturalEvent get event => widget.event;

  void onToggleFavorite() {
    widget.onToggleFavorite();
    setState(() => isFavorite = !isFavorite);
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: buildShareText(event), subject: event.title),
      );
    } catch (_) {
      _notify('No se pudo abrir el menú de compartir.');
    }
  }

  Future<void> _addToCalendar() async {
    final window = calendarWindowFor(event);
    final address = event.address.isEmpty ? '' : ', ${event.address}';
    try {
      final added = await calendar.Add2Calendar.addEvent2Cal(
        calendar.Event(
          title: event.title,
          description: event.hideLink
              ? ''
              : 'Más información: ${moreInfoTarget(event)}',
          location: '${event.place}$address',
          startDate: window.start,
          endDate: window.end,
          allDay: window.allDay,
        ),
      );
      if (!added) _notify('No se pudo abrir el calendario.');
    } catch (_) {
      _notify('No se pudo abrir el calendario.');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMoreInfo() async {
    final uri = Uri.parse(moreInfoTarget(event));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir la información del evento');
    }
  }

  /// La ficha oficial de la actividad, enlazada desde la cita de la fuente.
  Future<void> _openSource() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse(event.officialUrl);
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace.')),
    );
  }

  static const double _headerHeight = 300;

  @override
  void initState() {
    super.initState();
    _heroTag = EventHeroTag._take();
    _scroll.addListener(() {
      final collapsed =
          _scroll.hasClients &&
          _scroll.offset > _headerHeight - kToolbarHeight - 40;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _EventImage(event: event, iconSize: 84);
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: _headerHeight,
            backgroundColor: Brand.navy,
            foregroundColor: Colors.white,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: _collapsed
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                child: BackButton(
                  color: _collapsed ? Colors.white : Brand.navy,
                ),
              ),
            ),
            // El título aparece en la barra solo cuando la foto se ha plegado.
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _collapsed
                  ? Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _heroTag == null ? image : Hero(tag: _heroTag!, child: image),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.3, 0.7, 1.0],
                        colors: [
                          Color(0x550B2D4A),
                          Color(0x000B2D4A),
                          Color(0x000B2D4A),
                          Color(0x660B2D4A),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CategoryPill(category: event.category),
                  const SizedBox(height: 12),
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: Brand.navy,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        color: Brand.coralDeep,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _eventDateRange(event),
                          style: const TextStyle(
                            color: Brand.slate,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Brand.line),
                    ),
                    child: Column(
                      children: [
                        if (event.timeSlots.isNotEmpty) ...[
                          _InfoRow(
                            icon: Icons.access_time_rounded,
                            text: _eventTimeLabel(event),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _InfoRow(
                          icon: Icons.location_on_rounded,
                          text: event.address.isEmpty
                              ? event.place
                              : '${event.place}\n${event.address}',
                        ),
                        if (event.free) ...[
                          const SizedBox(height: 10),
                          const _InfoRow(
                            icon: Icons.sell_outlined,
                            text: 'Entrada gratuita',
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (event.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Descripción',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Brand.navy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      event.description,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Color(0xFF425B71),
                      ),
                    ),
                  ],
                  if (!event.hideLink) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openMoreInfo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Brand.navy,
                          side: const BorderSide(color: Brand.navy),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.language_rounded),
                        label: const Text(
                          'Más información',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  EventExtras(
                    event: event,
                    repository: widget.repository,
                    venues: widget.venues,
                  ),
                  // Fuente: solo en las actividades que se extraen de la
                  // agenda del Ayuntamiento, con enlace a su ficha oficial y
                  // la fecha de su última actualización.
                  if (event.fromAyuntamiento) ...[
                    const SizedBox(height: 22),
                    SourceLine(
                      updated: DateTime.tryParse(event.updatedAt),
                      onOpen: _openSource,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      // Acciones siempre a mano, aunque la descripción sea larga.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Brand.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _DetailAction(
                  icon: const Icon(Icons.share_outlined, color: Brand.navy),
                  label: 'Compartir',
                  onTap: _share,
                ),
                _DetailAction(
                  icon: const Icon(
                    Icons.event_available_outlined,
                    color: Brand.navy,
                  ),
                  label: 'Calendario',
                  onTap: _addToCalendar,
                ),
                _DetailAction(
                  icon: AnimatedHeartIcon(
                    isFavorite: isFavorite,
                    size: 24,
                    idleColor: Brand.navy,
                  ),
                  label: isFavorite ? 'Guardado' : 'Favorito',
                  semanticsLabel: isFavorite
                      ? 'Quitar de favoritos'
                      : 'Guardar como favorito',
                  onTap: () {
                    favoriteHaptic();
                    onToggleFavorite();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón de la barra inferior de la ficha: icono sobre texto.
class _DetailAction extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const _DetailAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: semanticsLabel ?? label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Brand.navy,
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF48617A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, color: Color(0xFF28415E)),
          ),
        ),
      ],
    );
  }
}

String _categoryLabel(CulturalCategory category) {
  switch (category) {
    case CulturalCategory.all:
      return 'Todos';
    case CulturalCategory.musica:
      return 'Música';
    case CulturalCategory.teatro:
      return 'Teatro';
    case CulturalCategory.exposiciones:
      return 'Exposiciones';
    case CulturalCategory.gastronomia:
      return 'Gastronomía';
    case CulturalCategory.cine:
      return 'Cine';
    case CulturalCategory.charlas:
      return 'Charlas y talleres';
    case CulturalCategory.eventos:
      return 'Otros eventos';
  }
}

Color _categoryColor(CulturalCategory category) {
  switch (category) {
    case CulturalCategory.all:
      return Colors.grey;
    case CulturalCategory.musica:
      return const Color(0xFF7B5FBF);
    case CulturalCategory.teatro:
      return const Color(0xFFD9822B);
    case CulturalCategory.exposiciones:
      return const Color(0xFFC2456B);
    case CulturalCategory.gastronomia:
      return const Color(0xFF43A66A);
    case CulturalCategory.cine:
      return const Color(0xFF3B5BDB);
    case CulturalCategory.charlas:
      return const Color(0xFF6C757D);
    case CulturalCategory.eventos:
      return Brand.navy;
  }
}

/// Imagen de una actividad, para usarla fuera de este archivo (portada).
class EventImage extends StatelessWidget {
  final CulturalEvent event;
  final double iconSize;

  const EventImage({super.key, required this.event, this.iconSize = 40});

  @override
  Widget build(BuildContext context) =>
      _EventImage(event: event, iconSize: iconSize);
}

/// Icono de una categoría.
IconData categoryIcon(CulturalCategory category) => _categoryIcon(category);

/// Nombre visible de una categoría («Música», «Teatro»...).
String categoryLabel(CulturalCategory category) => _categoryLabel(category);

/// Etiqueta de hora de una actividad («17:00 · 20:30»).
String eventTimeLabel(CulturalEvent event) => _eventTimeLabel(event);

/// Imagen de la actividad. Si no hay imagen o no carga, se muestra una
/// ilustración con el color y el icono de su categoría.
class _EventImage extends StatefulWidget {
  final CulturalEvent event;
  final double iconSize;

  const _EventImage({required this.event, this.iconSize = 64});

  @override
  State<_EventImage> createState() => _EventImageState();
}

class _EventImageState extends State<_EventImage> {
  int _index = 0;

  /// Orden de preferencia: imagen de la web de Zaragoza (si es propia del
  /// acto), imagen del banco de imágenes y, al final, la ilustración.
  List<String> get _candidates {
    final event = widget.event;
    return <String>[
      if (event.imageUrl.isNotEmpty && !event.genericImage) event.imageUrl,
      if (event.fallbackImageUrl.isNotEmpty) event.fallbackImageUrl,
    ];
  }

  Widget _placeholder() {
    final event = widget.event;
    final color = _categoryColor(event.category);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Brand.navy, 0.65)!],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        _categoryIcon(event.category),
        size: widget.iconSize,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    if (_index >= candidates.length) {
      return _placeholder();
    }
    return Image.network(
      candidates[_index],
      key: ValueKey(candidates[_index]),
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(),
      errorBuilder: (_, _, _) {
        // Si esta imagen falla, se prueba la siguiente en el siguiente frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _index++);
        });
        return _placeholder();
      },
    );
  }
}

/// Información legal y de origen de los datos.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _legalUrl =
      'https://www.zaragoza.es/sede/portal/aviso-legal';

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Brand.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF425B71),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _section(
              'Aplicación no oficial',
              '${Brand.name} es una aplicación independiente. No está '
                  'patrocinada ni respaldada por el Ayuntamiento de Zaragoza.',
            ),
            _section(
              'Origen de los datos',
              'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de '
                  'Cultura), a través de su agenda cultural en la sede '
                  'electrónica. Además, la agenda podrá incluir actividades '
                  'propias de esta aplicación y propuestas recibidas mediante '
                  'el formulario «Envía tu evento»; cuando sea así, se indicará '
                  'en la ficha de la actividad. La información se actualiza '
                  'periódicamente.',
            ),
            _section(
              'Elaboración propia',
              'Las categorías (música, teatro, exposiciones…) y la '
                  'agrupación de horarios los calcula esta aplicación para '
                  'facilitar la consulta, y pueden no coincidir con la '
                  'clasificación oficial. Consulta siempre la ficha oficial '
                  'antes de acudir.',
            ),
            _section(
              'Reutilización de la información',
              'La información del Ayuntamiento de Zaragoza se reproduce sin '
                  'alterar su sentido y con indicación de su origen y de la '
                  'fecha de su última actualización, conforme a las '
                  'condiciones generales para la reutilización de su aviso '
                  'legal. Esta aplicación es independiente: no está '
                  'patrocinada ni respaldada por el Ayuntamiento de Zaragoza.',
            ),
            _section(
              'Imágenes',
              'Las imágenes proceden de la web del Ayuntamiento y pertenecen '
                  'a sus titulares. Cuando una actividad no tiene una imagen '
                  'propia se muestra una foto orientativa de Pexels '
                  '(pexels.com), con el nombre de su autor.',
            ),
            _section(
              'Monumentos, rutas y servicios',
              'Los monumentos, museos y rutas proceden del Ayuntamiento de '
                  'Zaragoza y de Turismo de Zaragoza. Farmacias de guardia y '
                  'bibliotecas: Ayuntamiento de Zaragoza. Centros de salud: Servicio '
                  'Aragonés de Salud (Sector Zaragoza II) y Gobierno de Aragón, '
                  'Aragón Open Data (licencia CC BY 4.0).',
            ),
            _section(
              'Temperatura',
              '© AEMET. Información elaborada por la Agencia Estatal de '
                  'Meteorología (estación de Zaragoza Aeropuerto).',
            ),
            _section(
              'Mapas y ubicación',
              'Los mapas de «Cerca de mí» son de OpenStreetMap (© '
                  'colaboradores de OpenStreetMap). En las rutas, la '
                  'ubicación de algunos monumentos se calcula a partir de su '
                  'dirección con CartoCiudad (Instituto Geográfico Nacional); '
                  'el resto usa las coordenadas del Ayuntamiento de Zaragoza. '
                  'Pueden tener pequeños errores: comprueba siempre la '
                  'dirección.',
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_legalUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Condiciones generales para la reutilización'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: Brand.name,
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Licencias de código abierto'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ajustes: envío de eventos e información legal.
class SettingsScreen extends StatefulWidget {
  final bool remindersEnabled;

  /// Activa/desactiva los avisos. Devuelve si se pudo (p. ej. si el usuario
  /// concedió el permiso de notificaciones).
  final Future<bool> Function(bool enabled) onRemindersChanged;

  final LocationService locationService;

  const SettingsScreen({
    super.key,
    required this.remindersEnabled,
    required this.onRemindersChanged,
    this.locationService = const DeviceLocationService(),
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _reminders = widget.remindersEnabled;
  bool _locationAllowed = false;
  bool _crashReports = true;

  @override
  void initState() {
    super.initState();
    CrashReporter.isEnabled().then((enabled) {
      if (mounted) setState(() => _crashReports = enabled);
    });
    widget.locationService.hasPermission().then((allowed) {
      if (mounted) setState(() => _locationAllowed = allowed);
    });
  }

  /// Activar muestra el aviso del sistema. Android no permite quitar un
  /// permiso desde la app ni volver a pedirlo si el usuario marcó «No volver a
  /// preguntar»; en esos casos se ofrece ir a los ajustes del teléfono.
  Future<void> _toggleLocation(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = widget.locationService;
    SnackBar withSettings(String message) => SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Abrir ajustes',
        onPressed: service.openSettings,
      ),
    );

    if (!value) {
      messenger.showSnackBar(
        withSettings(
          'Para desactivar la ubicación, hazlo en los ajustes del teléfono.',
        ),
      );
      return;
    }
    final status = await service.requestPermission();
    if (!mounted) return;
    switch (status) {
      case LocationStatus.ok:
        setState(() => _locationAllowed = true);
      case LocationStatus.deniedForever:
        messenger.showSnackBar(
          withSettings(
            'Has bloqueado el permiso. Solo se puede activar en los ajustes del teléfono.',
          ),
        );
      default:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No se concedió el permiso de ubicación.'),
          ),
        );
    }
  }

  Future<void> _openUrl(String url, String errorMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
    }
  }

  Future<void> _rateApp() async {
    final messenger = ScaffoldMessenger.of(context);
    for (final url in <String>[
      'market://details?id=$_androidAppId',
      'https://play.google.com/store/apps/details?id=$_androidAppId',
    ]) {
      try {
        if (await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        )) {
          return;
        }
      } catch (_) {}
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir la tienda de aplicaciones.'),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Brand.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: Brand.navy),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _tile(
              icon: Icons.event_available_outlined,
              title: 'Envía tu evento',
              subtitle: '¿Organizas algo? Cuéntanoslo y lo revisaremos.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EventSubmissionScreen(),
                ),
              ),
            ),
            _tile(
              icon: Icons.tune,
              title: 'Mis preferencias',
              subtitle:
                  'Elige y ordena los tipos de actividad que más te gustan.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PreferencesScreen()),
              ),
            ),
            _tile(
              icon: Icons.notifications_active_outlined,
              title: 'Notificaciones',
              subtitle: 'Avisos de favoritos y sugerencias del fin de semana.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationSettingsScreen(
                    remindersEnabled: _reminders,
                    onRemindersChanged: (enabled) async {
                      final done = await widget.onRemindersChanged(enabled);
                      if (done) _reminders = enabled;
                      return done;
                    },
                  ),
                ),
              ),
            ),
            Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Brand.line),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                secondary: const Icon(Icons.my_location, color: Brand.navy),
                title: const Text(
                  'Ubicación para «Cerca de mí»',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Se usa solo en tu móvil para mostrarte las actividades cercanas. No se guarda.',
                ),
                value: _locationAllowed,
                onChanged: _toggleLocation,
              ),
            ),
            _tile(
              icon: Icons.lightbulb_outline,
              title: 'Sugerir mejoras',
              subtitle: 'Cuéntanos qué cambiarías de la app. ¡Te escuchamos!',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuggestionScreen()),
              ),
            ),
            Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Brand.line),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                secondary: const Icon(
                  Icons.bug_report_outlined,
                  color: Brand.navy,
                ),
                title: const Text(
                  'Enviar informes de errores',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Ayúdanos a mejorar la app. No incluye datos personales.',
                ),
                value: _crashReports,
                onChanged: (value) {
                  setState(() => _crashReports = value);
                  CrashReporter.setEnabled(value);
                },
              ),
            ),
            _tile(
              icon: Icons.star_outline,
              title: 'Valorar la app',
              subtitle: 'Cuéntanos qué te parece en la tienda de aplicaciones.',
              onTap: _rateApp,
            ),
            _tile(
              icon: Icons.privacy_tip_outlined,
              title: 'Política de privacidad',
              onTap: () => _openUrl(
                _privacyUrl,
                'No se pudo abrir la política de privacidad.',
              ),
            ),
            _tile(
              icon: Icons.info_outline,
              title: 'Acerca de y aviso legal',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
