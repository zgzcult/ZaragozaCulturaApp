/// «Hoy te recomendamos esto»: una actividad de hoy por cada categoría, entre
/// las que todavía se puede asistir.
library;

import 'package:flutter/material.dart';

import 'event_classifier.dart';
import 'main.dart';
import 'brand.dart';
import 'ui_kit.dart';

// ---------------------------------------------------------------------------
// Lógica
// ---------------------------------------------------------------------------

/// Orden en el que se muestran las categorías.
const List<CulturalCategory> suggestionCategories = [
  CulturalCategory.musica,
  CulturalCategory.teatro,
  CulturalCategory.exposiciones,
  CulturalCategory.gastronomia,
  CulturalCategory.cine,
  CulturalCategory.charlas,
  CulturalCategory.eventos,
];

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

/// Minutos que faltan para la próxima franja de hoy; null si no hay.
int? _minutesUntilStart(CulturalEvent event, DateTime now) {
  final current = now.hour * 60 + now.minute;
  int? best;
  for (final slot in event.timeSlots) {
    final minutes = _slotMinutes(slot);
    if (minutes != null && current < minutes.start) {
      final wait = minutes.start - current;
      if (best == null || wait < best) best = wait;
    }
  }
  return best;
}

String _clock(int minutesFromMidnight) {
  final h = (minutesFromMidnight ~/ 60).toString().padLeft(2, '0');
  final m = (minutesFromMidnight % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Elige, para cada categoría, la mejor actividad de hoy a la que aún se puede
/// asistir: se prefieren las de pocos días, las que están en marcha y las que
/// empiezan pronto. Las categorías sin actividades se omiten.
List<DaySuggestion> pickDaySuggestions(
  List<CulturalEvent> events, {
  required DateTime now,
}) {
  final suggestions = <DaySuggestion>[];
  for (final category in suggestionCategories) {
    CulturalEvent? best;
    var bestScore = -1 << 30;
    String bestReason = 'Disponible hoy';
    for (final event in events) {
      if (event.category != category) continue;
      final state = availabilityOf(event, now);
      if (state == Availability.finished) continue;

      var score = event.isLongRunning ? 0 : 30;
      String? reason;
      switch (state) {
        case Availability.running:
          score += 12;
          reason = 'Está en marcha ahora mismo';
        case Availability.upcoming:
          final wait = _minutesUntilStart(event, now) ?? 0;
          // Un poco más de puntos cuanto antes empieza (hasta 6 h).
          score += 8 + ((360 - wait.clamp(0, 360)) ~/ 60);
          reason = 'Empieza a las ${_clock(now.hour * 60 + now.minute + wait)}';
        case Availability.allDay:
          score -= 5;
        case Availability.finished:
          break;
      }
      if (!event.isLongRunning) reason ??= 'Solo se celebra unos días';

      final better =
          best == null ||
          score > bestScore ||
          (score == bestScore && event.title.compareTo(best.title) < 0);
      if (better) {
        best = event;
        bestScore = score;
        bestReason = reason ?? 'Disponible hoy';
      }
    }
    if (best != null) {
      suggestions.add(DaySuggestion(event: best, reason: bestReason));
    }
  }
  return suggestions;
}

// ---------------------------------------------------------------------------
// Pantalla
// ---------------------------------------------------------------------------

class SuggestionOfDayScreen extends StatefulWidget {
  final ZaragozaEventsRepository repository;

  /// Hora actual; se puede fijar en los tests.
  final DateTime Function() clock;

  const SuggestionOfDayScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.clock = DateTime.now,
  });

  @override
  State<SuggestionOfDayScreen> createState() => _SuggestionOfDayScreenState();
}

class _SuggestionOfDayScreenState extends State<SuggestionOfDayScreen> {
  final FavoritesStorage _favoritesStorage = FavoritesStorage();
  final Set<String> _favorites = <String>{};
  List<CulturalEvent> _events = const <CulturalEvent>[];
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
    final fresh = await widget.repository.fetchFresh();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _events = fresh;
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
              color: Brand.navy,
            ),
          ),
        ),
        _card(suggestion.event),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = pickDaySuggestions(_events, now: widget.clock());

    Widget body;
    if (_loading) {
      body = const SkeletonList();
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
          const Text(
            'Una propuesta de cada tipo, para hoy.',
            style: TextStyle(fontSize: 14, color: Color(0xFF66758A)),
          ),
          for (final suggestion in suggestions) _suggestionItem(suggestion),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Hoy te recomendamos esto')),
      body: body,
    );
  }
}
