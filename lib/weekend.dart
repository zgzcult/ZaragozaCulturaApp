/// «Sugerencias fin de semana»: hasta tres actividades de cada tipo para el
/// sábado y el domingo, en el orden de «Mis preferencias».
library;

import 'package:flutter/material.dart';

import 'brand.dart';
import 'day_suggestion.dart';
import 'event_classifier.dart';
import 'main.dart';
import 'preferences.dart';
import 'ui_kit.dart';

/// Actividades de un tipo para el fin de semana.
class WeekendGroup {
  final CulturalCategory category;
  final List<CulturalEvent> events;

  const WeekendGroup({required this.category, required this.events});
}

String _key(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Días del fin de semana que toca: de lunes a viernes, el sábado y el
/// domingo que vienen; el sábado, hoy y mañana; el domingo, solo hoy.
List<DateTime> weekendDays(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (today.weekday == DateTime.sunday) return [today];
  final saturday = today.add(Duration(days: DateTime.saturday - today.weekday));
  return [saturday, saturday.add(const Duration(days: 1))];
}

const _weekdayNames = ['', '', '', '', '', '', 'sábado', 'domingo'];
const _monthNames = [
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

/// «Sábado 10 y domingo 11 de octubre».
String weekendLabel(DateTime now) {
  final days = weekendDays(now);
  String day(DateTime d) => '${_weekdayNames[d.weekday]} ${d.day}';
  String month(DateTime d) => 'de ${_monthNames[d.month - 1]}';
  final first = days.first, last = days.last;
  final text = days.length == 1
      ? '${day(first)} ${month(first)}'
      : first.month == last.month
      ? '${day(first)} y ${day(last)} ${month(last)}'
      : '${day(first)} ${month(first)} y ${day(last)} ${month(last)}';
  return text[0].toUpperCase() + text.substring(1);
}

/// Hasta [perCategory] actividades de cada tipo para el fin de semana, con
/// los tipos en el orden que prefiere el usuario. Primero las que solo duran
/// unos días (lo demás, como una exposición de meses, se puede ver cualquier
/// otro día); una misma actividad no se repite aunque se celebre los dos días.
List<WeekendGroup> pickWeekendSuggestions(
  List<CulturalEvent> events, {
  required DateTime now,
  List<CulturalCategory> preferred = const [],
  int perCategory = 3,
}) {
  final days = {for (final d in weekendDays(now)) _key(d)};
  final today = _key(now);
  final groups = <WeekendGroup>[];
  for (final category in categoriesByPreference(preferred)) {
    final candidates = [
      for (final event in events)
        if (event.category == category &&
            days.contains(event.date) &&
            // Si ya es fin de semana, lo que ha terminado hoy no se sugiere.
            !(event.date == today &&
                availabilityOf(event, now) == Availability.finished))
          event,
    ];
    candidates.sort((a, b) {
      if (a.isLongRunning != b.isLongRunning) return a.isLongRunning ? 1 : -1;
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.title.compareTo(b.title);
    });
    final picked = <CulturalEvent>[];
    final titles = <String>{};
    for (final event in candidates) {
      if (picked.length >= perCategory) break;
      if (titles.add(normalizeForSearch(event.title))) picked.add(event);
    }
    if (picked.isNotEmpty) {
      groups.add(WeekendGroup(category: category, events: picked));
    }
  }
  return groups;
}

class WeekendScreen extends StatefulWidget {
  final ZaragozaEventsRepository repository;
  final DateTime Function() clock;

  const WeekendScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.clock = DateTime.now,
  });

  @override
  State<WeekendScreen> createState() => _WeekendScreenState();
}

class _WeekendScreenState extends State<WeekendScreen> {
  List<CulturalEvent> _events = const [];
  List<CulturalCategory> _preferred = const [];
  final Set<String> _favorites = <String>{};
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
    final favorites = await FavoritesStorage().load();
    final preferred = await CategoryPreferences.load();
    final cached = await widget.repository.loadCached();
    if (!mounted) return;
    setState(() {
      _favorites
        ..clear()
        ..addAll(favorites);
      _preferred = preferred;
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
    await toggleStoredFavorite(id, repository: widget.repository);
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

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final Widget body;
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
                style: TextStyle(color: Brand.slate, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    } else {
      final groups = pickWeekendSuggestions(
        _events,
        now: now,
        preferred: _preferred,
      );
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(
            weekendLabel(now),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Brand.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _preferred.isEmpty
                ? 'Elige tus intereses en Ajustes › Mis preferencias y te '
                      'los enseñaremos primero.'
                : 'Ordenadas según tus preferencias.',
            style: const TextStyle(color: Brand.slate, height: 1.4),
          ),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Text(
                'Todavía no hay actividades publicadas para este fin de '
                'semana. Vuelve a mirar en unos días.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.slate, height: 1.4),
              ),
            ),
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 22, bottom: 12),
              child: Row(
                children: [
                  Icon(categoryIcon(group.category), color: Brand.coralDeep),
                  const SizedBox(width: 10),
                  Text(
                    categoryLabel(group.category),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Brand.navy,
                    ),
                  ),
                ],
              ),
            ),
            for (final event in group.events)
              EventCard(
                event: event,
                isFavorite: _favorites.contains(event.id),
                onFavorite: () => _toggleFavorite(event.id),
                onOpen: () => _open(event),
              ),
          ],
        ],
      );
    }
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Sugerencias fin de semana')),
      body: body,
    );
  }
}
