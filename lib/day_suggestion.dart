/// «Sugerencia del día»: actividades de hoy a las que aún se puede asistir,
/// ordenadas según el tiempo (aire libre con buen tiempo, interior si no).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'event_classifier.dart';
import 'main.dart';

const String _weatherUrl = 'https://zaragoza-cultura-app.onrender.com/weather';

// ---------------------------------------------------------------------------
// Tiempo
// ---------------------------------------------------------------------------

class DayWeather {
  /// Buen tiempo para estar en la calle (sin lluvia, temperatura agradable).
  final bool favorable;

  /// Texto corto para mostrar: «Soleado, 22 °C».
  final String summary;

  const DayWeather({required this.favorable, required this.summary});

  static DayWeather? fromJson(dynamic json) {
    if (json is! Map || json['favorable'] is! bool) return null;
    return DayWeather(
      favorable: json['favorable'] as bool,
      summary: (json['summary'] ?? '').toString(),
    );
  }
}

/// Origen del tiempo de hoy. Se puede sustituir en los tests.
abstract class WeatherSource {
  const WeatherSource();

  /// El tiempo de hoy, o null si no está disponible.
  Future<DayWeather?> today();
}

class HttpWeatherSource extends WeatherSource {
  const HttpWeatherSource();

  @override
  Future<DayWeather?> today() async {
    try {
      final response = await http
          .get(Uri.parse(_weatherUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      return DayWeather.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Lógica
// ---------------------------------------------------------------------------

enum Setting { indoor, outdoor, unknown }

final RegExp _outdoorPattern = RegExp(
  r'\b(parque|plaza|paseo|jardin(es)?|anfiteatro|calle|ribera|riberas|escenario|'
  r'aire libre|pasarela|mercadillo|explanada|huerta|cementerio|rio ebro|'
  r'avenida|avda|camino|puente|isla)\b',
);
final RegExp _indoorPattern = RegExp(
  r'\b(teatro|museo|auditorio|centro civico|biblioteca|sala|palacio|iglesia|'
  r'catedral|basilica|cine|caixaforum|iaacc|aula|pabellon|centro de|casa de|'
  r'universidad|paraninfo|lonja|harinera|centro cultural|convivencia|galeria)\b',
);

/// ¿La actividad es al aire libre o en un recinto cubierto? Se deduce del
/// nombre del lugar (y, si no basta, del título); si no se sabe, `unknown`.
Setting settingOf(CulturalEvent event) {
  final place = normalizeForSearch(event.place);
  final title = normalizeForSearch(event.title);
  final indoorPlace = _indoorPattern.hasMatch(place);
  final outdoorPlace = _outdoorPattern.hasMatch(place);
  // «Centro Cívico ... Parque X»: gana el recinto cubierto.
  if (indoorPlace) return Setting.indoor;
  if (outdoorPlace) return Setting.outdoor;
  if (_outdoorPattern.hasMatch(title)) return Setting.outdoor;
  if (_indoorPattern.hasMatch(title)) return Setting.indoor;
  return Setting.unknown;
}

({int start, int? end})? _slotMinutes(String slot) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?:\s*[–-]\s*(\d{1,2}):(\d{2}))?')
      .firstMatch(slot.trim());
  if (match == null) return null;
  final start = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  final end = match.group(3) == null
      ? null
      : int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
  return (start: start, end: end);
}

/// Duración que se supone cuando solo se conoce la hora de comienzo.
const int _assumedMinutes = 120;

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Estado de una actividad de hoy respecto a [now].
enum Availability { running, upcoming, finished, allDay }

/// ¿Se puede asistir hoy todavía? Compara la hora actual con las franjas de
/// la actividad; sin horario conocido, se considera disponible todo el día.
Availability availabilityOf(CulturalEvent event, DateTime now) {
  if (event.date != _dateKey(now)) return Availability.finished;
  if (event.timeSlots.isEmpty) return Availability.allDay;
  final current = now.hour * 60 + now.minute;
  var upcoming = false;
  for (final slot in event.timeSlots) {
    final minutes = _slotMinutes(slot);
    if (minutes == null) continue;
    final end = minutes.end ?? (minutes.start + _assumedMinutes);
    if (current >= minutes.start && current < end) return Availability.running;
    if (current < minutes.start) upcoming = true;
  }
  return upcoming ? Availability.upcoming : Availability.finished;
}

class DaySuggestion {
  final CulturalEvent event;
  final String reason;

  const DaySuggestion({required this.event, required this.reason});
}

/// Hora de comienzo de la próxima franja de hoy («19:00»), o null.
String? _nextStart(CulturalEvent event, DateTime now) {
  final current = now.hour * 60 + now.minute;
  for (final slot in event.timeSlots) {
    final minutes = _slotMinutes(slot);
    if (minutes != null && current < minutes.start) {
      final h = (minutes.start ~/ 60).toString().padLeft(2, '0');
      final m = (minutes.start % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }
  }
  return null;
}

/// Elige hasta [count] actividades para hoy. Puntúa a favor las de pocos
/// días, las que encajan con el tiempo y las que empiezan pronto; y evita
/// repetir categoría.
List<DaySuggestion> pickDaySuggestions(
  List<CulturalEvent> events, {
  required DateTime now,
  DayWeather? weather,
  int count = 3,
}) {
  final candidates =
      <({CulturalEvent event, Availability state, int score, String reason})>[];
  for (final event in events) {
    final state = availabilityOf(event, now);
    if (state == Availability.finished) continue;

    var score = 0;
    String? reason;
    if (!event.isLongRunning) score += 30;
    final setting = settingOf(event);
    if (weather != null && setting != Setting.unknown) {
      final matches =
          (weather.favorable && setting == Setting.outdoor) ||
          (!weather.favorable && setting == Setting.indoor);
      score += matches ? 25 : -25;
      if (matches) {
        reason = weather.favorable
            ? 'Hace buen tiempo y es al aire libre'
            : 'Con este tiempo, un plan de interior';
      }
    }
    switch (state) {
      case Availability.running:
        score += 12;
        reason ??= 'Está en marcha ahora mismo';
      case Availability.upcoming:
        score += 8;
        final start = _nextStart(event, now);
        if (start != null) reason ??= 'Empieza a las $start';
      case Availability.allDay:
        score -= 5;
      case Availability.finished:
        break;
    }
    if (!event.isLongRunning) reason ??= 'Solo se celebra unos días';
    candidates.add((
      event: event,
      state: state,
      score: score,
      reason: reason ?? 'Disponible hoy',
    ));
  }

  // Selección voraz: la mejor, y a las siguientes se les resta puntos si ya
  // hay otra de su misma categoría.
  final picked = <DaySuggestion>[];
  final categories = <CulturalCategory>{};
  final pool = [...candidates]
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.event.title.compareTo(b.event.title);
    });
  while (picked.length < count && pool.isNotEmpty) {
    var bestIndex = 0;
    var bestScore = -1 << 30;
    for (var i = 0; i < pool.length; i++) {
      final penalty = categories.contains(pool[i].event.category) ? 15 : 0;
      final adjusted = pool[i].score - penalty;
      if (adjusted > bestScore) {
        bestScore = adjusted;
        bestIndex = i;
      }
    }
    final chosen = pool.removeAt(bestIndex);
    categories.add(chosen.event.category);
    picked.add(DaySuggestion(event: chosen.event, reason: chosen.reason));
  }
  return picked;
}

// ---------------------------------------------------------------------------
// Pantalla
// ---------------------------------------------------------------------------

class SuggestionOfDayScreen extends StatefulWidget {
  final ZaragozaEventsRepository repository;
  final WeatherSource weatherSource;

  /// Hora actual; se puede fijar en los tests.
  final DateTime Function() clock;

  const SuggestionOfDayScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.weatherSource = const HttpWeatherSource(),
    this.clock = DateTime.now,
  });

  @override
  State<SuggestionOfDayScreen> createState() => _SuggestionOfDayScreenState();
}

class _SuggestionOfDayScreenState extends State<SuggestionOfDayScreen> {
  final FavoritesStorage _favoritesStorage = FavoritesStorage();
  final Set<String> _favorites = <String>{};
  List<CulturalEvent> _events = const <CulturalEvent>[];
  DayWeather? _weather;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _events.isEmpty;
      _failed = false;
    });
    final favorites = await _favoritesStorage.load();
    final cached = await widget.repository.loadCached();
    if (!mounted) return;
    setState(() {
      _favorites
        ..clear()
        ..addAll(favorites);
      if (cached.isNotEmpty) {
        _events = cached;
        _loading = false;
      }
    });
    // El tiempo y las actividades se piden a la vez.
    final results = await Future.wait<Object?>([
      widget.repository.fetchFresh(),
      widget.weatherSource.today(),
    ]);
    if (!mounted) return;
    final fresh = results[0] as List<CulturalEvent>?;
    setState(() {
      if (fresh != null) _events = fresh;
      _weather = results[1] as DayWeather?;
      _failed = fresh == null && _events.isEmpty;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() {
      if (!_favorites.remove(id)) _favorites.add(id);
    });
    await _favoritesStorage.save(_favorites);
  }

  void _open(CulturalEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          isFavorite: _favorites.contains(event.id),
          onToggleFavorite: () => _toggleFavorite(event.id),
        ),
      ),
    );
  }

  Widget _card(CulturalEvent event) => EventCard(
    event: event,
    isFavorite: _favorites.contains(event.id),
    onFavorite: () => _toggleFavorite(event.id),
    onOpen: () => _open(event),
  );

  Widget _weatherBanner(DayWeather weather) {
    final color = weather.favorable
        ? const Color(0xFFE8F5EC)
        : const Color(0xFFEAF0F7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            weather.favorable
                ? Icons.wb_sunny_outlined
                : Icons.umbrella_outlined,
            color: const Color(0xFF1E5F74),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                if (weather.summary.isNotEmpty) weather.summary,
                weather.favorable
                    ? 'Buen día para planes al aire libre'
                    : 'Mejor un plan de interior',
              ].join(' · '),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF10243E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionItem(DaySuggestion suggestion) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            suggestion.reason,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E5F74),
            ),
          ),
        ),
        _card(suggestion.event),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final suggestions = pickDaySuggestions(
      _events,
      now: now,
      weather: _weather,
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No se pudieron cargar las actividades. Comprueba tu conexión.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF66758A), height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    } else if (suggestions.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Hoy ya no quedan actividades a las que asistir. '
            'Mira la agenda de mañana en «Actividades».',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF66758A), height: 1.4),
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (_weather != null) ...[
            _weatherBanner(_weather!),
            const SizedBox(height: 14),
          ],
          const Text(
            'Te recomendamos',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF10243E),
            ),
          ),
          _suggestionItem(suggestions.first),
          if (suggestions.length > 1) ...[
            const SizedBox(height: 18),
            const Text(
              'Otras ideas para hoy',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF10243E),
              ),
            ),
            for (final suggestion in suggestions.skip(1))
              _suggestionItem(suggestion),
          ],
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      appBar: AppBar(title: const Text('Sugerencia del día')),
      body: body,
    );
  }
}
