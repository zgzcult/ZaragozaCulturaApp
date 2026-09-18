import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const List<String> _eventsApiUrls = <String>[
  'http://10.0.2.2:8000/events',
  'http://localhost:8000/events',
  'http://127.0.0.1:8000/events',
];
const String _fallbackAssetPath = 'assets/sample_events.json';

void main() {
  runApp(const ZaragozaCulturaApp());
}

enum CulturalCategory { all, musica, teatro, gastronomia, eventos }

CulturalCategory culturalCategoryFromString(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();

  switch (normalized) {
    case 'musica':
    case 'música':
      return CulturalCategory.musica;
    case 'teatro':
      return CulturalCategory.teatro;
    case 'gastronomia':
    case 'gastronomía':
      return CulturalCategory.gastronomia;
    case 'eventos':
    case 'eventos culturales':
    case 'exposiciones':
    case 'conferencias':
    case 'cine':
    case 'infantil':
      return CulturalCategory.eventos;
    default:
      return CulturalCategory.eventos;
  }
}

String _isoDateKey(DateTime date) {
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).toIso8601String().split('T').first;
}

String _dateLabel(DateTime date) {
  final weekday = <String>[
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ][date.weekday - 1];
  return '$weekday\n${date.day}';
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

String _absoluteImageUrl(String value) {
  if (value.startsWith('//')) {
    return 'https:$value';
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
  });

  factory CulturalEvent.fromJson(Map<String, dynamic> json) {
    return CulturalEvent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Evento').toString(),
      description: (json['description'] ?? '').toString(),
      category: culturalCategoryFromString(json['category'] as String?),
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

List<CulturalEvent> _parseEventList(dynamic decoded) {
  final items = decoded is List
      ? decoded
      : (decoded is Map ? decoded['events'] ?? [] : <dynamic>[]);

  if (items is! List) {
    return const <CulturalEvent>[];
  }

  return items
      .map(
        (item) =>
            CulturalEvent.fromJson(Map<String, dynamic>.from(item as Map)),
      )
      .toList();
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
      place: 'Plaza del Pilar',
      officialUrl: 'https://www.zaragoza.es',
    ),
  ];
}

class ZaragozaEventsRepository {
  final List<String> apiUrls;
  final String fallbackAssetPath;

  const ZaragozaEventsRepository({
    this.apiUrls = _eventsApiUrls,
    this.fallbackAssetPath = _fallbackAssetPath,
  });

  Future<List<CulturalEvent>> loadEvents() async {
    for (final apiUrl in apiUrls) {
      try {
        final response = await http
            .get(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final parsed = _parseEventList(decoded);
          if (parsed.isNotEmpty) {
            return parsed;
          }
        }
      } catch (_) {}
    }

    try {
      final content = await rootBundle.loadString(fallbackAssetPath);
      final decoded = jsonDecode(content);
      final parsed = _parseEventList(decoded);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } catch (_) {}

    return buildFallbackEvents();
  }
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
  const ZaragozaCulturaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zaragoza Cultura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F8FC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E5F74),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E5F74),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const AgendaScreen(),
    );
  }
}

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final ZaragozaEventsRepository _repository = const ZaragozaEventsRepository();
  final FavoritesStorage _favoritesStorage = FavoritesStorage();
  final Set<String> _favoriteEventIds = <String>{};

  final List<DateTime> _calendarDays = List<DateTime>.generate(45, (index) {
    final date = DateTime.now().add(Duration(days: index));
    return DateTime(date.year, date.month, date.day);
  });

  DateTime selectedDate = DateTime.now();
  CulturalCategory selectedCategory = CulturalCategory.all;
  bool favoritesOnly = false;
  List<CulturalEvent> _events = <CulturalEvent>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
    _loadData();
  }

  Future<void> _loadData() async {
    final events = await _repository.loadEvents();
    final favorites = await _favoritesStorage.load();

    if (!mounted) {
      return;
    }

    setState(() {
      _events = events;
      _favoriteEventIds
        ..clear()
        ..addAll(favorites);
      _isLoading = false;
    });
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      bottomNavigationBar: NavigationBar(
        selectedIndex: favoritesOnly ? 2 : 0,
        onDestinationSelected: (index) {
          if (index == 2) {
            setState(() => favoritesOnly = !favoritesOnly);
          } else if (index == 0 && favoritesOnly) {
            setState(() => favoritesOnly = false);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favoritos',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Ajustes',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            favoritesOnly
                                ? 'Tus favoritos'
                                : 'Zaragoza Cultura',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10243E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Zaragoza · ${_monthLabel(selectedDate)}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF738196),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DateStripDelegate(
                      dates: _calendarDays,
                      selectedDate: selectedDate,
                      onSelected: (date) => setState(() => selectedDate = date),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 58,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                        scrollDirection: Axis.horizontal,
                        itemCount: CulturalCategory.values.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final category = CulturalCategory.values[index];
                          return ChoiceChip(
                            label: Text(_categoryLabel(category)),
                            selected: selectedCategory == category,
                            onSelected: (_) =>
                                setState(() => selectedCategory = category),
                            selectedColor: const Color(0xFF2463D9),
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(
                              color: selectedCategory == category
                                  ? Colors.white
                                  : const Color(0xFF1D2939),
                              fontWeight: FontWeight.w700,
                            ),
                            side: const BorderSide(color: Color(0xFFE0E5EC)),
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
                                color: Color(0xFF10243E),
                              ),
                            ),
                          ),
                          Text(
                            '${filteredEvents.length} actividades',
                            style: const TextStyle(
                              color: Color(0xFF66758A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (filteredEvents.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No hay actividades para este día.',
                          style: TextStyle(color: Color(0xFF66758A)),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final event = filteredEvents[index];
                          final isFavorite = _favoriteEventIds.contains(
                            event.id,
                          );
                          return _EventCard(
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
                        }, childCount: filteredEvents.length),
                      ),
                    ),
                ],
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
  double get minExtent => 76;

  @override
  double get maxExtent => 126;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final cardHeight = 94 - (progress * 24);
    final numberSize = 24 - (progress * 7);
    return Container(
      color: const Color(0xFFF8FAFD),
      padding: EdgeInsets.only(top: 8 - (progress * 4), bottom: 8, left: 20),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final selected = _isoDateKey(date) == _isoDateKey(selectedDate);
          return GestureDetector(
            onTap: () => onSelected(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: progress > .5 ? 58 : 74,
              height: cardHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF2463D9) : Colors.white,
                borderRadius: BorderRadius.circular(progress > .5 ? 16 : 20),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF2463D9)
                      : const Color(0xFFE0E5EC),
                ),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x242463D9),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _weekdayShort(date),
                    style: TextStyle(
                      fontSize: progress > .5 ? 10 : 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xFF738196),
                    ),
                  ),
                  SizedBox(height: progress > .5 ? 2 : 6),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: numberSize,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xFF10243E),
                    ),
                  ),
                ],
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

class _EventCard extends StatelessWidget {
  final CulturalEvent event;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  const _EventCard({
    required this.event,
    required this.isFavorite,
    required this.onFavorite,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D10243E),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 168,
                  width: double.infinity,
                  child: event.imageUrl.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _categoryColor(event.category),
                                const Color(0xFF10243E),
                              ],
                            ),
                          ),
                          child: Icon(
                            _categoryIcon(event.category),
                            size: 64,
                            color: Colors.white70,
                          ),
                        )
                      : Image.network(
                          event.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: _categoryColor(event.category),
                            child: Icon(
                              _categoryIcon(event.category),
                              size: 64,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _categoryLabel(event.category),
                      style: TextStyle(
                        color: _categoryColor(event.category),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: onFavorite,
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite
                          ? const Color(0xFFE5484D)
                          : const Color(0xFF66758A),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10243E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.access_time_rounded,
                    text: event.time.isEmpty
                        ? 'Horario por confirmar'
                        : event.time,
                  ),
                  const SizedBox(height: 7),
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

IconData _categoryIcon(CulturalCategory category) {
  switch (category) {
    case CulturalCategory.musica:
      return Icons.music_note;
    case CulturalCategory.teatro:
      return Icons.theater_comedy;
    case CulturalCategory.gastronomia:
      return Icons.restaurant;
    case CulturalCategory.eventos:
      return Icons.event;
    case CulturalCategory.all:
      return Icons.auto_awesome;
  }
}

class EventDetailScreen extends StatelessWidget {
  final CulturalEvent event;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  Future<void> _openMoreInfo() async {
    final targetUrl = event.moreInfoUrl.isEmpty
        ? event.officialUrl
        : event.moreInfoUrl;
    final uri = Uri.parse(targetUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir la información del evento');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      event.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: _categoryColor(event.category),
                        child: Icon(
                          _categoryIcon(event.category),
                          size: 64,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              if (event.imageUrl.isNotEmpty) const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E5F74), Color(0xFF2C7C9B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _categoryLabel(event.category),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: onToggleFavorite,
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: Colors.white,
                          ),
                          tooltip: 'Favorito',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      event.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _eventDateRange(event),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE4ECF4)),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.access_time_rounded,
                      text: event.time.isEmpty
                          ? 'Horario por confirmar'
                          : event.endTime.isEmpty
                          ? event.time
                          : '${event.time} - ${event.endTime}',
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      text: event.address.isEmpty
                          ? event.place
                          : '${event.place}\n${event.address}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Descripción',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF102A43),
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openMoreInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E5F74),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.language_rounded),
                  label: const Text(
                    'Más información',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onToggleFavorite,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E5F74),
                    side: const BorderSide(color: Color(0xFFB9D3E2)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  label: Text(
                    isFavorite
                        ? 'Quitar de favoritos'
                        : 'Guardar como favorito',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
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
    case CulturalCategory.gastronomia:
      return 'Gastronomía';
    case CulturalCategory.eventos:
      return 'Eventos';
  }
}

Color _categoryColor(CulturalCategory category) {
  switch (category) {
    case CulturalCategory.all:
      return Colors.grey;
    case CulturalCategory.musica:
      return const Color(0xFF7B5FBF);
    case CulturalCategory.teatro:
      return const Color(0xFFED9B3A);
    case CulturalCategory.gastronomia:
      return const Color(0xFF43A66A);
    case CulturalCategory.eventos:
      return const Color(0xFF1E5F74);
  }
}
