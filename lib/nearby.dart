/// "Cerca de mí": actividades ordenadas por distancia y mapa con marcadores.
///
/// La ubicación del usuario se usa solo en el dispositivo, mientras la
/// pantalla está abierta: no se guarda ni se envía a ningún servidor.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show CulturalEvent;

/// Plaza del Pilar: punto de partida cuando no hay ubicación.
const double zaragozaCenterLat = 41.6563;
const double zaragozaCenterLng = -0.8773;

/// Debe coincidir con el applicationId de Android (los servidores de mapas lo
/// usan para identificar la app).
const String _tileUserAgent = 'com.example.zaragoza_cultura_app';

// ---------------------------------------------------------------------------
// Lógica de distancias (sin interfaz, fácil de probar)
// ---------------------------------------------------------------------------

/// Distancia en metros entre dos puntos (fórmula de Haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
}

/// "350 m", "1,2 km"...
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = math.max(10, (meters / 10).round() * 10);
    return '$rounded m';
  }
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Una actividad cercana: su fecha más próxima dentro del periodo elegido.
class NearbyActivity {
  final CulturalEvent event;
  final double meters;

  const NearbyActivity({required this.event, required this.meters});
}

/// Actividades con coordenadas a menos de [radiusMeters] de ([lat], [lng]) y
/// con fecha entre [fromDate] y [toDate] (AAAA-MM-DD, ambas incluidas).
/// Cada actividad (título y lugar) aparece una vez, con su fecha más próxima
/// dentro del periodo. Ordenadas de la más cercana a la más lejana.
List<NearbyActivity> nearbyActivities(
  List<CulturalEvent> events, {
  required double lat,
  required double lng,
  required double radiusMeters,
  required String fromDate,
  required String toDate,
}) {
  final best = <String, NearbyActivity>{};
  for (final event in events) {
    final eventLat = event.lat;
    final eventLng = event.lng;
    if (eventLat == null || eventLng == null) continue;
    if (event.date.compareTo(fromDate) < 0 ||
        event.date.compareTo(toDate) > 0) {
      continue;
    }
    final meters = distanceMeters(lat, lng, eventLat, eventLng);
    if (meters > radiusMeters) continue;
    final key = '${event.title}|${event.place}';
    final current = best[key];
    if (current == null || event.date.compareTo(current.event.date) < 0) {
      best[key] = NearbyActivity(event: event, meters: meters);
    }
  }
  final list = best.values.toList()
    ..sort((a, b) {
      final byDistance = a.meters.compareTo(b.meters);
      return byDistance != 0
          ? byDistance
          : a.event.title.compareTo(b.event.title);
    });
  return list;
}

// ---------------------------------------------------------------------------
// Ubicación del dispositivo
// ---------------------------------------------------------------------------

enum LocationStatus { ok, denied, deniedForever, serviceDisabled, error }

class LocationResult {
  final LocationStatus status;
  final double? lat;
  final double? lng;

  const LocationResult(this.status, {this.lat, this.lng});
}

/// Acceso a la ubicación. Se puede sustituir en los tests.
abstract class LocationService {
  const LocationService();

  /// Obtiene la posición actual. Con [askPermission] en `false` no muestra el
  /// aviso del sistema: solo responde si ya hay permiso.
  Future<LocationResult> locate({required bool askPermission});

  Future<void> openSettings();
}

class DeviceLocationService extends LocationService {
  const DeviceLocationService();

  @override
  Future<LocationResult> locate({required bool askPermission}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && askPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationStatus.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const LocationResult(LocationStatus.denied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationResult(
        LocationStatus.ok,
        lat: position.latitude,
        lng: position.longitude,
      );
    } catch (_) {
      return const LocationResult(LocationStatus.error);
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Pantalla
// ---------------------------------------------------------------------------

enum _Phase { asking, locating, ready, problem }

enum _Period { today, tomorrow, week }

class NearbyScreen extends StatefulWidget {
  final List<CulturalEvent> events;
  final LocationService locationService;

  /// "Hoy · miércoles, 30 de septiembre" para una fecha AAAA-MM-DD.
  final String Function(String isoDate) dayLabel;

  /// Horario legible de una actividad ("" si no hay).
  final String Function(CulturalEvent event) timeLabel;

  final void Function(CulturalEvent event) onOpen;

  /// En los tests se desactivan los mapas descargados de internet.
  final bool enableTiles;

  const NearbyScreen({
    super.key,
    required this.events,
    required this.dayLabel,
    required this.timeLabel,
    required this.onOpen,
    this.locationService = const DeviceLocationService(),
    this.enableTiles = true,
  });

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  static const List<int> _radiiKm = [1, 3, 5, 10];

  _Phase _phase = _Phase.asking;
  LocationStatus _problem = LocationStatus.error;
  double _lat = zaragozaCenterLat;
  double _lng = zaragozaCenterLng;
  bool _isUserLocation = false;

  _Period _period = _Period.today;
  int _radiusKm = 3;
  final MapController _map = MapController();

  @override
  void initState() {
    super.initState();
    // Si ya hay permiso, se localiza sin preguntar de nuevo.
    _locate(askPermission: false, silentIfDenied: true);
  }

  Future<void> _locate({
    required bool askPermission,
    bool silentIfDenied = false,
  }) async {
    setState(() => _phase = _Phase.locating);
    final result = await widget.locationService.locate(
      askPermission: askPermission,
    );
    if (!mounted) return;
    if (result.status == LocationStatus.ok) {
      setState(() {
        _lat = result.lat!;
        _lng = result.lng!;
        _isUserLocation = true;
        _phase = _Phase.ready;
      });
      return;
    }
    setState(() {
      _problem = result.status;
      _phase = silentIfDenied && result.status == LocationStatus.denied
          ? _Phase.asking
          : _Phase.problem;
    });
  }

  void _useCityCenter() {
    setState(() {
      _lat = zaragozaCenterLat;
      _lng = zaragozaCenterLng;
      _isUserLocation = false;
      _phase = _Phase.ready;
    });
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  ({String from, String to}) get _range {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    switch (_period) {
      case _Period.today:
        return (from: _isoDate(base), to: _isoDate(base));
      case _Period.tomorrow:
        final tomorrow = base.add(const Duration(days: 1));
        return (from: _isoDate(tomorrow), to: _isoDate(tomorrow));
      case _Period.week:
        return (
          from: _isoDate(base),
          to: _isoDate(base.add(const Duration(days: 6))),
        );
    }
  }

  double _zoomFor(int km) => switch (km) {
    1 => 15.0,
    3 => 14.0,
    5 => 13.0,
    _ => 12.0,
  };

  Widget _message({
    required IconData icon,
    required String text,
    required List<Widget> actions,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: const Color(0xFF1E5F74)),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF425B71),
                height: 1.45,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            ...actions,
          ],
        ),
      ),
    );
  }

  Widget _askingView() {
    return _message(
      icon: Icons.near_me_outlined,
      text:
          'Para enseñarte lo que hay cerca, la app necesita saber dónde estás.\n\n'
          'Tu ubicación se usa solo en tu móvil, mientras tengas esta pantalla '
          'abierta. No se guarda ni se envía a ningún servidor.',
      actions: [
        FilledButton.icon(
          onPressed: () => _locate(askPermission: true),
          icon: const Icon(Icons.my_location),
          label: const Text('Usar mi ubicación'),
        ),
        TextButton(
          onPressed: _useCityCenter,
          child: const Text('Ver desde el centro de Zaragoza'),
        ),
      ],
    );
  }

  Widget _problemView() {
    final (text, actions) = switch (_problem) {
      LocationStatus.deniedForever => (
        'Has bloqueado el permiso de ubicación. Puedes activarlo en los ajustes del teléfono.',
        <Widget>[
          FilledButton(
            onPressed: widget.locationService.openSettings,
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
      LocationStatus.serviceDisabled => (
        'La ubicación del teléfono está desactivada. Actívala y vuelve a intentarlo.',
        <Widget>[
          FilledButton(
            onPressed: () => _locate(askPermission: true),
            child: const Text('Reintentar'),
          ),
        ],
      ),
      LocationStatus.denied => (
        'Sin permiso de ubicación no podemos saber qué hay cerca de ti.',
        <Widget>[
          FilledButton(
            onPressed: () => _locate(askPermission: true),
            child: const Text('Permitir ubicación'),
          ),
        ],
      ),
      _ => (
        'No se pudo obtener tu ubicación. Comprueba el GPS e inténtalo de nuevo.',
        <Widget>[
          FilledButton(
            onPressed: () => _locate(askPermission: true),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    };
    return _message(
      icon: Icons.location_off_outlined,
      text: text,
      actions: [
        ...actions,
        TextButton(
          onPressed: _useCityCenter,
          child: const Text('Ver desde el centro de Zaragoza'),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFF2463D9),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF1D2939),
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: Color(0xFFE0E5EC)),
    );
  }

  /// Una actividad de la lista de un lugar: tarjeta con fondo, borde y franja
  /// de color (siempre el mismo), título en negrita, fecha y horario.
  Widget _venueActivityCard(BuildContext sheetContext, NearbyActivity item) {
    final time = widget.timeLabel(item.event);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFEAF3F7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.pop(sheetContext);
            widget.onOpen(item.event);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFD8E5)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E5F74),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.event.title,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10243E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 14,
                                color: Color(0xFF1E5F74),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.dayLabel(item.event.date),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF425B71),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: Color(0xFF1E5F74),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    time,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF425B71),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.chevron_right, color: Color(0xFF1E5F74)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVenue(List<NearbyActivity> here) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              here.first.event.place,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final item in here) _venueActivityCard(sheetContext, item),
          ],
        ),
      ),
    );
  }

  Widget _mapView(List<NearbyActivity> results, String summary) {
    // Un marcador por lugar, con el número de actividades que hay allí.
    final byVenue = <String, List<NearbyActivity>>{};
    for (final item in results) {
      final key =
          '${item.event.lat!.toStringAsFixed(5)},${item.event.lng!.toStringAsFixed(5)}';
      byVenue.putIfAbsent(key, () => <NearbyActivity>[]).add(item);
    }
    final markers = <Marker>[
      for (final here in byVenue.values)
        Marker(
          point: LatLng(here.first.event.lat!, here.first.event.lng!),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showVenue(here),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1E5F74),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 4),
                ],
              ),
              child: Text(
                '${here.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      if (_isUserLocation)
        Marker(
          point: LatLng(_lat, _lng),
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2463D9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 5),
              ],
            ),
          ),
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: LatLng(_lat, _lng),
              initialZoom: _zoomFor(_radiusKm),
              minZoom: 10,
              maxZoom: 18,
              backgroundColor: const Color(0xFFE6EDF3),
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (widget.enableTiles)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: _tileUserAgent,
                ),
              MarkerLayer(markers: markers),
              if (widget.enableTiles)
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Color(0x22000000), blurRadius: 4),
                  ],
                ),
                child: Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF425B71),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _readyView() {
    final range = _range;
    final results = nearbyActivities(
      widget.events,
      lat: _lat,
      lng: _lng,
      radiusMeters: _radiusKm * 1000.0,
      fromDate: range.from,
      toDate: range.to,
    );
    final origin = _isUserLocation ? 'de ti' : 'de la Plaza del Pilar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final entry in const {
                _Period.today: 'Hoy',
                _Period.tomorrow: 'Mañana',
                _Period.week: 'Esta semana',
              }.entries) ...[
                _chip(
                  entry.value,
                  _period == entry.key,
                  () => setState(() => _period = entry.key),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final km in _radiiKm) ...[
                _chip('$km km', _radiusKm == km, () {
                  setState(() => _radiusKm = km);
                  _map.move(LatLng(_lat, _lng), _zoomFor(km));
                }),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Solo el mapa: las actividades se ven al tocar un marcador.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: _mapView(
              results,
              results.isEmpty
                  ? 'Sin actividades a menos de $_radiusKm km $origin. '
                        'Prueba con más radio o con "Esta semana".'
                  : '${results.length} ${results.length == 1 ? 'actividad' : 'actividades'} '
                        'a menos de $_radiusKm km $origin',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Text(
              'Cerca de mí',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF10243E),
              ),
            ),
          ),
          Expanded(
            child: switch (_phase) {
              _Phase.asking => _askingView(),
              _Phase.locating => const Center(
                child: CircularProgressIndicator(),
              ),
              _Phase.problem => _problemView(),
              _Phase.ready => _readyView(),
            },
          ),
        ],
      ),
    );
  }
}
