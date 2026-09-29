import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'event_classifier.dart';

const List<String> _eventsApiUrls = <String>[
  'https://zaragoza-cultura-app.onrender.com/events',
  'http://10.0.2.2:8000/events',
  'http://localhost:8000/events',
  'http://127.0.0.1:8000/events',
];
const String _fallbackAssetPath = 'assets/sample_events.json';

void main() {
  runApp(const ZaragozaCulturaApp());
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

const String _sourceNotice =
    'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de Cultura).';
const String _ownWorkNotice =
    'Las categorías y la agrupación de horarios son elaboración de esta '
    'aplicación, que no es oficial.';

String _updatedLabel(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return '';
  return ' Actualizado el ${date.day}/${date.month}/${date.year}.';
}

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
    );
  }

  CulturalEvent withTimeSlots(List<String> slots) {
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
  for (final event in events) {
    final key = '${event.title}|${event.place}|${event.date}';
    final slot = _timeSlotOf(event);
    merged.putIfAbsent(key, () => event);
    final set = slots.putIfAbsent(key, () => <String>{});
    if (slot.isNotEmpty) set.add(slot);
  }
  return merged.entries.map((entry) {
    final list = slots[entry.key]!.toList()..sort();
    return entry.value.withTimeSlots(list);
  }).toList();
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
  bool _isRefreshing = false;
  bool _loadFailed = false;

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
    if (!mounted) {
      return;
    }
    setState(() {
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
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            );
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
                                        color: Color(0xFF66758A),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    const Icon(
                                      Icons.cloud_off,
                                      size: 18,
                                      color: Color(0xFF66758A),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'No se pudo actualizar. Mostrando datos guardados.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF66758A),
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
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
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
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
                        child: Text(
                          'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de Cultura). '
                          'Aplicación no oficial.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF738196),
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
                  child: _EventImage(event: event),
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
                  if (event.timeSlots.isNotEmpty) ...[
                    _InfoRow(
                      icon: Icons.access_time_rounded,
                      text: _eventTimeLabel(event),
                    ),
                    const SizedBox(height: 7),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _EventImage(event: event, iconSize: 84),
                ),
              ),
              if (event.imageCredit.isNotEmpty &&
                  (event.imageUrl.isEmpty || event.genericImage)) ...[
                const SizedBox(height: 6),
                Text(
                  '${event.imageCredit} (imagen orientativa)',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF738196),
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
              const SizedBox(height: 20),
              Text(
                '$_sourceNotice${_updatedLabel(event.updatedAt)} '
                '$_ownWorkNotice',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF738196),
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
      return const Color(0xFF1E5F74);
  }
}

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
          colors: [color, Color.lerp(color, const Color(0xFF10243E), 0.65)!],
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
              color: Color(0xFF10243E),
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
              'Zaragoza Cultura es una aplicación independiente. No está '
                  'patrocinada ni respaldada por el Ayuntamiento de Zaragoza.',
            ),
            _section(
              'Origen de los datos',
              'Origen de los datos: Ayuntamiento de Zaragoza (Servicio de Cultura) '
                  '(agenda cultural de la sede electrónica). La información se '
                  'actualiza periódicamente; cada actividad indica la fecha de '
                  'su última actualización.',
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
              'Imágenes',
              'Las imágenes proceden de la web del Ayuntamiento y pertenecen '
                  'a sus titulares. Cuando una actividad no tiene una imagen '
                  'propia se muestra una foto orientativa de Pexels '
                  '(pexels.com), con el nombre de su autor.',
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_legalUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Aviso legal del Ayuntamiento'),
            ),
          ],
        ),
      ),
    );
  }
}
