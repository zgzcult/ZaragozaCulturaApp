/// Restaurantes en un mapa. Origen de los datos: Ayuntamiento de Zaragoza.
///
/// Los marcadores se agrupan por proximidad y se separan al acercar el mapa.
/// Al tocar uno se abre una tarjeta con el nombre, la dirección y el enlace a
/// su ficha de Google Maps.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'event_classifier.dart';
import 'nearby.dart';
import 'brand.dart';

const String _placesUrl =
    'https://zaragoza-cultura-app.onrender.com/places?type=restaurante';
const String _placesCacheKey = 'cached_places_restaurante';

/// Debe coincidir con el applicationId de Android.
const String _tileUserAgent = 'com.example.zaragoza_cultura_app';

class Place {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String url;
  final double? lat;
  final double? lng;

  const Place({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
    this.address = '',
    this.phone = '',
    this.url = '',
  });

  /// ¿Tiene coordenadas para ponerlo en el mapa? Los que no, salen solo en
  /// la lista y se localizan con Google Maps.
  bool get hasLocation => lat != null && lng != null;

  static Place? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    final name = (json['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    return Place(
      id: (json['id'] ?? name).toString(),
      name: name,
      address: (json['address'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      lat: lat,
      lng: lng,
    );
  }
}

List<Place> parsePlaces(dynamic decoded) {
  final places = <Place>[];
  if (decoded is! List) return places;
  for (final item in decoded) {
    if (item is! Map) continue;
    final place = Place.fromJson(Map<String, dynamic>.from(item));
    if (place != null) places.add(place);
  }
  return places;
}

/// Enlace a la ficha de Google Maps del lugar (gratis, sin clave). Google
/// muestra allí sus valoraciones y opiniones.
Uri googleMapsLink(Place place) {
  final query = [
    place.name,
    place.address,
    'Zaragoza',
  ].where((part) => part.trim().isNotEmpty).join(' ');
  return Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
}

// ---------------------------------------------------------------------------
// Agrupación de marcadores
// ---------------------------------------------------------------------------

class PlaceCluster {
  final double lat;
  final double lng;
  final List<Place> places;

  const PlaceCluster({
    required this.lat,
    required this.lng,
    required this.places,
  });

  bool get isSingle => places.length == 1;
}

/// A partir de este zoom ya no se agrupan los marcadores.
const double maxClusterZoom = 17.5;

/// Agrupa los lugares que quedarían a menos de [cellPixels] píxeles unos de
/// otros al nivel de zoom [zoom]. Con zoom alto, cada lugar queda aparte.
List<PlaceCluster> clusterPlaces(
  List<Place> places, {
  required double zoom,
  double cellPixels = 56,
}) {
  // Con el zoom casi al máximo no se agrupa: si no, dos restaurantes en el
  // mismo edificio no se podrían separar nunca.
  final located = places.where((place) => place.hasLocation).toList();
  if (zoom >= maxClusterZoom) {
    return [
      for (final place in located)
        PlaceCluster(lat: place.lat!, lng: place.lng!, places: [place]),
    ];
  }
  final scale = 256 * math.pow(2, zoom);
  final cells = <String, List<Place>>{};
  for (final place in located) {
    final x = (place.lng! + 180) / 360 * scale;
    final sinLat = math.sin(place.lat! * math.pi / 180);
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
    final key = '${(x / cellPixels).floor()}:${(y / cellPixels).floor()}';
    cells.putIfAbsent(key, () => <Place>[]).add(place);
  }
  return [
    for (final group in cells.values)
      PlaceCluster(
        lat: group.map((p) => p.lat!).reduce((a, b) => a + b) / group.length,
        lng: group.map((p) => p.lng!).reduce((a, b) => a + b) / group.length,
        places: group,
      ),
  ];
}

// ---------------------------------------------------------------------------
// Datos
// ---------------------------------------------------------------------------

/// Carga de lugares. Se puede sustituir en los tests.
abstract class PlacesRepository {
  const PlacesRepository();

  /// Lo guardado en el teléfono en la última descarga correcta.
  Future<List<Place>> loadCached();

  /// Descarga del servidor; null si no se pudo.
  Future<List<Place>?> fetchFresh();
}

class HttpPlacesRepository extends PlacesRepository {
  const HttpPlacesRepository();

  @override
  Future<List<Place>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_placesCacheKey);
      return raw == null ? const <Place>[] : parsePlaces(jsonDecode(raw));
    } catch (_) {
      return const <Place>[];
    }
  }

  @override
  Future<List<Place>?> fetchFresh() async {
    try {
      final response = await http
          .get(Uri.parse(_placesUrl))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final places = parsePlaces(jsonDecode(body));
      if (places.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_placesCacheKey, body);
      return places;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Pantalla
// ---------------------------------------------------------------------------

class RestaurantsScreen extends StatefulWidget {
  final PlacesRepository repository;
  final LocationService locationService;

  /// En los tests se desactivan los mapas descargados de internet.
  final bool enableTiles;

  const RestaurantsScreen({
    super.key,
    this.repository = const HttpPlacesRepository(),
    this.locationService = const DeviceLocationService(),
    this.enableTiles = true,
  });

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  /// Zoom a partir del cual se muestran los nombres bajo los marcadores.
  static const double _labelZoom = 16;

  final MapController _map = MapController();
  List<Place> _places = const <Place>[];
  List<Place> _sorted = const <Place>[];
  bool _showList = false;
  String _query = '';
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  bool _failed = false;
  double _zoom = 13;
  LatLng? _user;

  @override
  void initState() {
    super.initState();
    _load();
    _locateSilently();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Guarda los lugares y los ordena alfabéticamente para la lista.
  void _setPlaces(List<Place> places) {
    _places = places;
    _sorted = [...places]
      ..sort(
        (a, b) =>
            normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
      );
  }

  Future<void> _load() async {
    setState(() {
      _loading = _places.isEmpty;
      _failed = false;
    });
    final cached = await widget.repository.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _setPlaces(cached);
        _loading = false;
      });
    }
    final fresh = await widget.repository.fetchFresh();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _setPlaces(fresh);
      _failed = fresh == null && _places.isEmpty;
      _loading = false;
    });
  }

  /// Si ya hay permiso, centra el mapa en el usuario sin preguntar nada.
  Future<void> _locateSilently() async {
    final result = await widget.locationService.locate(askPermission: false);
    if (!mounted || result.status != LocationStatus.ok) return;
    _moveToUser(result);
  }

  Future<void> _locateWithPrompt() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.locationService.locate(askPermission: true);
    if (!mounted) return;
    if (result.status == LocationStatus.ok) {
      _moveToUser(result);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo obtener tu ubicación. Revisa el permiso y el GPS.',
          ),
        ),
      );
    }
  }

  void _moveToUser(LocationResult result) {
    final point = LatLng(result.lat!, result.lng!);
    setState(() => _user = point);
    _map.move(point, 15);
  }

  void _openCluster(PlaceCluster cluster) {
    if (cluster.isSingle) {
      _showPlace(cluster.places.first);
    } else {
      _map.move(LatLng(cluster.lat, cluster.lng), math.min(_zoom + 2, 18));
    }
  }

  Future<void> _openGoogleMaps(Place place) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        googleMapsLink(place),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Maps.')),
      );
    }
  }

  void _showPlace(Place place) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _PlaceCard(
            place: place,
            onGoogleMaps: () {
              Navigator.pop(sheetContext);
              _openGoogleMaps(place);
            },
          ),
        ),
      ),
    );
  }

  Widget _marker(PlaceCluster cluster, bool showLabel) {
    if (!cluster.isSingle) {
      return GestureDetector(
        onTap: () => _openCluster(cluster),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFB4561B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 4),
            ],
          ),
          child: Text(
            '${cluster.places.length}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }
    final place = cluster.places.first;
    return GestureDetector(
      onTap: () => _openCluster(cluster),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFD9822B),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 4),
              ],
            ),
            child: const Icon(Icons.restaurant, color: Colors.white, size: 20),
          ),
          if (showLabel)
            Positioned(
              top: 42,
              left: -55,
              width: 150,
              child: Text(
                place.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Brand.navy,
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 3),
                    Shadow(color: Colors.white, blurRadius: 3),
                    Shadow(color: Colors.white, blurRadius: 6),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapView() {
    final clusters = clusterPlaces(_places, zoom: _zoom);
    final showLabels = _zoom >= _labelZoom;
    final markers = <Marker>[
      for (final cluster in clusters)
        Marker(
          point: LatLng(cluster.lat, cluster.lng),
          width: cluster.isSingle ? 38 : 46,
          height: cluster.isSingle ? 38 : 46,
          child: _marker(cluster, showLabels),
        ),
      if (_user != null)
        Marker(
          point: _user!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Brand.navy,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 5),
              ],
            ),
          ),
        ),
    ];

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: const LatLng(zaragozaCenterLat, zaragozaCenterLng),
        initialZoom: _zoom,
        minZoom: 10,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE6EDF3),
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (camera, _) {
          if ((camera.zoom - _zoom).abs() > 0.05) {
            setState(() => _zoom = camera.zoom);
          }
        },
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
    );
  }

  /// Lista con buscador: todos los restaurantes, también los que no tienen
  /// coordenadas y por tanto no están en el mapa.
  Widget _listView() {
    final terms = normalizeForSearch(_query)
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    final items = terms.isEmpty
        ? _sorted
        : _sorted.where((place) {
            final text = normalizeForSearch('${place.name} ${place.address}');
            return terms.every(text.contains);
          }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Nombre o calle',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Text(
            terms.isEmpty
                ? '${_places.length} restaurantes'
                : '${items.length} de ${_places.length} restaurantes',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF425B71),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'Ningún restaurante coincide con tu búsqueda.',
                    style: TextStyle(color: Color(0xFF66758A)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final place = items[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showPlace(place),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Brand.line),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        place.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Brand.navy,
                                        ),
                                      ),
                                      if (place.address.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            place.address,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF66758A),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Brand.navy,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _mapWithCount() {
    final onMap = _places.where((place) => place.hasLocation).length;
    return Stack(
      children: [
        Positioned.fill(child: _mapView()),
        Positioned(
          top: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 4),
              ],
            ),
            child: Text(
              onMap == 1
                  ? '1 restaurante en el mapa'
                  : '$onMap restaurantes en el mapa',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF425B71),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showTabs = !_loading && !_failed;
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Restaurantes')),
      floatingActionButton: showTabs && !_showList
          ? FloatingActionButton.small(
              tooltip: 'Mi ubicación',
              onPressed: _locateWithPrompt,
              child: const Icon(Icons.my_location),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No se pudieron cargar los restaurantes. Comprueba tu conexión.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF66758A), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.map_outlined),
                          label: Text('Mapa'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.list),
                          label: Text('Lista'),
                        ),
                      ],
                      selected: {_showList},
                      onSelectionChanged: (selection) =>
                          setState(() => _showList = selection.first),
                    ),
                  ),
                ),
                Expanded(child: _showList ? _listView() : _mapWithCount()),
              ],
            ),
    );
  }
}

/// Tarjeta de un restaurante, con el mismo aspecto que las de actividades:
/// fondo azul claro, borde, franja de color y título en negrita.
class _PlaceCard extends StatelessWidget {
  final Place place;
  final VoidCallback onGoogleMaps;

  const _PlaceCard({required this.place, required this.onGoogleMaps});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Brand.navy),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF425B71)),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Brand.skyTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.skyLine),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: const BoxDecoration(
                color: Brand.navy,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: Brand.navy,
                      ),
                    ),
                    if (place.address.isNotEmpty)
                      row(Icons.location_on_outlined, place.address),
                    if (place.phone.isNotEmpty)
                      row(Icons.phone_outlined, place.phone),
                    if (!place.hasLocation)
                      row(
                        Icons.info_outline,
                        'No aparece en el mapa de la app. Usa Google Maps para llegar.',
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onGoogleMaps,
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.navy,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Ver en Google Maps'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
