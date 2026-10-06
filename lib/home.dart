/// Pantalla principal de Maña Zaragoza: saludo según la hora, accesos
/// compactos a las secciones (agenda, monumentos, rutas y servicios), las
/// recomendaciones de hoy en tarjetas cuadradas y bloques deslizables de rutas
/// y monumentos imprescindibles.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'brand.dart';
import 'day_suggestion.dart';
import 'main.dart';
import 'monuments.dart';
import 'nearby.dart';
import 'notifications_screen.dart';
import 'preferences.dart';
import 'reminders.dart';
import 'routes.dart';
import 'ui_kit.dart';
import 'useful_services.dart';

const String _weatherUrl = 'https://zaragoza-cultura-app.onrender.com/weather';

/// Temperatura actual en Zaragoza (AEMET, a través de nuestro servidor).
abstract class WeatherRepository {
  const WeatherRepository();

  /// Grados redondeados, o null si no se sabe.
  Future<int?> currentTemperature();
}

class HttpWeatherRepository extends WeatherRepository {
  const HttpWeatherRepository();

  @override
  Future<int?> currentTemperature() async {
    try {
      final response = await http
          .get(Uri.parse(_weatherUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final temp = data is Map ? data['temp'] : null;
      return temp is num ? temp.round() : null;
    } catch (_) {
      return null;
    }
  }
}

/// «Buenos días», «Buenas tardes» o «Buenas noches» según la hora.
String greetingFor(DateTime now) {
  if (now.hour >= 6 && now.hour < 13) return 'Buenos días';
  if (now.hour >= 13 && now.hour < 21) return 'Buenas tardes';
  return 'Buenas noches';
}

const _weekdays = [
  'LUNES',
  'MARTES',
  'MIÉRCOLES',
  'JUEVES',
  'VIERNES',
  'SÁBADO',
  'DOMINGO',
];
const _months = [
  'ENERO',
  'FEBRERO',
  'MARZO',
  'ABRIL',
  'MAYO',
  'JUNIO',
  'JULIO',
  'AGOSTO',
  'SEPTIEMBRE',
  'OCTUBRE',
  'NOVIEMBRE',
  'DICIEMBRE',
];

/// «VIERNES 2 DE OCTUBRE · 17°» (sin temperatura si no se conoce).
String headerDateLabel(DateTime now, int? temperature) {
  final date =
      '${_weekdays[now.weekday - 1]} ${now.day} DE ${_months[now.month - 1]}';
  return temperature == null ? date : '$date · $temperature°';
}

class HomeScreen extends StatefulWidget {
  final ZaragozaEventsRepository repository;
  final LocationService locationService;
  final MonumentsRepository monumentsRepository;
  final ServicesRepository servicesRepository;
  final WeatherRepository weatherRepository;
  final DateTime Function() clock;

  const HomeScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.locationService = const DeviceLocationService(),
    this.monumentsRepository = const HttpMonumentsRepository(),
    this.servicesRepository = const HttpServicesRepository(),
    this.weatherRepository = const HttpWeatherRepository(),
    this.clock = DateTime.now,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<DaySuggestion>? _suggestions;
  List<Monument>? _monuments;
  int? _temperature;
  final FavoritesStorage _favoritesStorage = FavoritesStorage();
  final Set<String> _favorites = <String>{};
  final ReminderService _reminders = ReminderService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Al pulsar un aviso de favoritos se abre su actividad, tanto si la app
    // estaba abierta como si se abre con el aviso.
    ReminderService.onOpen = _openEventById;
    _reminders.launchEventId().then((eventId) {
      if (mounted && eventId != null) _openEventById(eventId);
    });
    ReminderInbox.refresh();
    _loadSuggestions();
    _loadMonuments();
    widget.weatherRepository.currentTemperature().then((value) {
      if (mounted && value != null) setState(() => _temperature = value);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ReminderService.onOpen == _openEventById) ReminderService.onOpen = null;
    super.dispose();
  }

  /// Al volver a la app puede haber llegado un aviso mientras tanto.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ReminderInbox.refresh();
  }

  /// Abre la ficha de una actividad por su identificador y da por leído su
  /// aviso.
  void _openEventById(String eventId) {
    if (!mounted) return;
    ReminderInbox.markRead(eventId: eventId);
    _open(EventLinkScreen(eventId: eventId, repository: widget.repository));
  }

  void _openNotifications() =>
      _open(NotificationsScreen(repository: widget.repository));

  /// Usa lo guardado en el teléfono; solo descarga si no hay nada.
  Future<void> _loadSuggestions() async {
    final favorites = await _favoritesStorage.load();
    final preferred = await CategoryPreferences.load();
    var events = await widget.repository.loadCached();
    if (events.isEmpty) events = await widget.repository.fetchFresh() ?? [];
    if (!mounted) return;
    setState(() {
      _favorites
        ..clear()
        ..addAll(favorites);
      _suggestions = pickDaySuggestions(
        events,
        now: widget.clock(),
        preferred: preferred,
      );
    });
  }

  Future<void> _loadMonuments() async {
    final cached = await widget.monumentsRepository.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) setState(() => _monuments = cached);
    final fresh = await widget.monumentsRepository.fetchFresh();
    if (!mounted) return;
    setState(() => _monuments = fresh ?? _monuments ?? const []);
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openSettings() async {
    final reminders = await loadRemindersEnabled();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          remindersEnabled: reminders,
          onRemindersChanged: (enabled) =>
              setFavoriteReminders(enabled, repository: widget.repository),
          locationService: widget.locationService,
        ),
      ),
    );
    // Puede haber cambiado las preferencias: se reordenan las recomendaciones.
    if (mounted) _loadSuggestions();
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() {
      if (!_favorites.remove(id)) _favorites.add(id);
    });
    // Guarda el favorito y, si los avisos están activados, los reprograma.
    await toggleStoredFavorite(id, repository: widget.repository);
  }

  void _openEvent(CulturalEvent event) {
    _open(
      EventDetailScreen(
        event: event,
        isFavorite: _favorites.contains(event.id),
        onToggleFavorite: () => _toggleFavorite(event.id),
      ),
    );
  }

  void _openAgenda() => _open(
    AgendaScreen(
      repository: widget.repository,
      locationService: widget.locationService,
    ),
  );

  void _openSuggestions() =>
      _open(SuggestionOfDayScreen(repository: widget.repository));

  void _openMonuments() =>
      _open(MonumentsScreen(repository: widget.monumentsRepository));

  void _openRoutes() =>
      _open(RoutesScreen(repository: widget.monumentsRepository));

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final top = [
      for (final m in _monuments ?? const <Monument>[])
        if (m.top) m,
    ];
    return Scaffold(
      backgroundColor: Brand.cream,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          headerDateLabel(now, _temperature),
                          style: const TextStyle(
                            fontSize: 11.5,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                            color: Brand.coralDeep,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: ReminderInbox.unread,
                        builder: (context, unread, _) => IconButton(
                          tooltip: unread == 0
                              ? 'Avisos'
                              : unread == 1
                              ? 'Avisos: 1 sin leer'
                              : 'Avisos: $unread sin leer',
                          onPressed: _openNotifications,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Brand.navy,
                            side: const BorderSide(color: Brand.line),
                          ),
                          icon: Badge(
                            isLabelVisible: unread > 0,
                            label: Text('$unread'),
                            backgroundColor: Brand.coral,
                            textColor: Brand.navy,
                            child: const Icon(Icons.notifications_outlined),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ajustes',
                        onPressed: _openSettings,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Brand.navy,
                          side: const BorderSide(color: Brand.line),
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // El logo, a la izquierda y en la misma línea del saludo.
                  Row(
                    children: [
                      Image.asset(
                        'assets/brand/logo.png',
                        width: 56,
                        filterQuality: FilterQuality.high,
                        semanticLabel: Brand.name,
                        errorBuilder: (_, _, _) => const SizedBox(width: 56),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${greetingFor(now)},\nmañ@',
                            style: const TextStyle(
                              fontSize: 28,
                              height: 1.12,
                              fontWeight: FontWeight.w700,
                              color: Brand.navy,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _Shortcut(
                    icon: Icons.calendar_month_outlined,
                    label: 'Agenda',
                    color: Brand.skyDeep,
                    onTap: _openAgenda,
                  ),
                  _Shortcut(
                    icon: Icons.account_balance_outlined,
                    label: 'Monumentos',
                    color: Brand.navy,
                    onTap: _openMonuments,
                  ),
                  _Shortcut(
                    icon: Icons.alt_route_outlined,
                    label: 'Rutas',
                    color: Brand.skyDeep,
                    onTap: _openRoutes,
                  ),
                  _Shortcut(
                    icon: Icons.health_and_safety_outlined,
                    label: 'Servicios',
                    color: Brand.green,
                    onTap: () => _open(
                      UsefulServicesScreen(
                        repository: widget.servicesRepository,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Hoy te recomendamos
            if (_suggestions == null || _suggestions!.isNotEmpty) ...[
              _BlockHeader(
                title: 'Hoy te recomendamos',
                action: 'Ver todo',
                onAction: _openSuggestions,
              ),
              if (_suggestions == null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _SkeletonGrid(),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      for (final suggestion in _suggestions!)
                        _SuggestionTile(
                          suggestion: suggestion,
                          now: now,
                          onTap: () => _openEvent(suggestion.event),
                        ),
                    ],
                  ),
                ),
            ],
            // Rutas
            _BlockHeader(
              title: 'Rutas para descubrir Zaragoza',
              action: 'Ver todas',
              onAction: _openRoutes,
            ),
            _monuments == null
                ? const SizedBox(
                    height: 120,
                    child: _SkeletonRow(width: 190, height: 120),
                  )
                : RoutesCarousel(
                    monuments: _monuments!,
                    height: 120,
                    cardWidth: 190,
                  ),
            // Imprescindibles
            if (_monuments == null || top.isNotEmpty) ...[
              _BlockHeader(
                title: 'Imprescindibles',
                action: 'Ver todos',
                onAction: _openMonuments,
              ),
              SizedBox(
                height: 168,
                child: _monuments == null
                    ? const _SkeletonRow(width: 132, height: 168)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: top.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) => _MonumentTile(
                          monument: top[index],
                          onTap: () =>
                              _open(MonumentDetailScreen(monument: top[index])),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Acceso compacto a una sección: icono en un cuadrado redondeado y nombre.
class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Shortcut({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Brand.line),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F0B2D4A),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
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

class _BlockHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;

  const _BlockHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Brand.navy,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: Brand.coralDeep),
            child: Text(
              action,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (var i = 0; i < 4; i++)
            const SkeletonBox(height: double.infinity, radius: 18),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonRow({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SkeletonBox(width: width, height: height, radius: 18),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta cuadrada de una actividad recomendada hoy.
class _SuggestionTile extends StatelessWidget {
  final DaySuggestion suggestion;
  final DateTime now;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.suggestion,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final event = suggestion.event;
    final state = availabilityOf(event, now);
    final tag = switch (state) {
      Availability.running => 'Ahora',
      Availability.upcoming =>
        event.timeSlots.isEmpty
            ? 'Hoy'
            : event.timeSlots.first.split(' ').first,
      _ => 'Hoy',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B2D4A),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    EventImage(event: event),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: state == Availability.running
                              ? Brand.coral
                              : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            // Azul marino sobre coral: el blanco no se lee.
                            color: state == Availability.running
                                ? Brand.navy
                                : Brand.coralDeep,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Brand.navy,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Text(
                  categoryLabel(event.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Brand.slate),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta pequeña de un monumento imprescindible.
class _MonumentTile extends StatelessWidget {
  final Monument monument;
  final VoidCallback onTap;

  const _MonumentTile({required this.monument, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Brand.navy, Brand.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(Icons.account_balance_outlined, color: Colors.white38),
      ),
    );
    return SizedBox(
      width: 132,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Brand.navy,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (monument.image.isEmpty)
                  placeholder
                else
                  Image.network(
                    monument.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.35, 1.0],
                      colors: [Color(0x000B2D4A), Color(0xE60B2D4A)],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Text(
                    monument.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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
