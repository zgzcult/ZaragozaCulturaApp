/// Rutas para descubrir Zaragoza. Son las rutas oficiales de Turismo de
/// Zaragoza (Ayuntamiento); las introducciones están redactadas a partir de
/// sus páginas, que se citan en cada ruta. Las paradas son monumentos del
/// listado oficial, con su ficha completa.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'monuments.dart';
import 'ui_kit.dart';

class RouteStop {
  /// Id del monumento en el listado oficial, o null si la parada es un lugar
  /// sin ficha (una plaza).
  final String? monumentId;

  /// Nombre a mostrar si no es un monumento.
  final String name;

  /// Detalle de la parada según la página oficial de la ruta.
  final String note;

  const RouteStop.monument(this.monumentId, {this.note = ''}) : name = '';

  const RouteStop.place(this.name, {this.note = ''}) : monumentId = null;
}

class CityRoute {
  final String id;
  final String title;
  final String subtitle;
  final String intro;

  /// Duración de la visita guiada oficial, si la página la indica.
  final String guidedDuration;
  final String sourceUrl;
  final IconData icon;
  final List<RouteStop> stops;

  const CityRoute({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.intro,
    required this.sourceUrl,
    required this.icon,
    required this.stops,
    this.guidedDuration = '',
  });
}

const String _turismo = 'https://www.zaragoza.es/sede/portal/turismo';

const List<CityRoute> cityRoutes = [
  CityRoute(
    id: 'caesaraugusta',
    title: 'Zaragoza romana',
    subtitle: 'Ruta de Caesaraugusta',
    icon: Icons.account_balance_outlined,
    intro:
        'Zaragoza nació como colonia romana en el año 14 a. C. con el nombre '
        'de Caesaraugusta. Esta ruta sigue el trazado de aquella ciudad por el '
        'casco histórico: la muralla, el foro, las termas, el teatro y el '
        'puerto fluvial, cuyos restos se visitan hoy en museos municipales.',
    sourceUrl: '$_turismo/post/ruta-de-cesar-augusta',
    stops: [
      RouteStop.monument('monumento-1'),
      RouteStop.monument(
        'monumento-2',
        note: 'Centro de la vida social, religiosa, política y económica.',
      ),
      RouteStop.monument(
        'monumento-4',
        note: 'Lugar de encuentro de la sociedad romana, entre el foro y el teatro.',
      ),
      RouteStop.monument(
        'monumento-5',
        note: 'Uno de los mayores de Hispania, con más de 6.000 espectadores.',
      ),
      RouteStop.monument(
        'monumento-3',
        note: 'El tercer puerto en importancia de Hispania.',
      ),
    ],
  ),
  CityRoute(
    id: 'mudejar',
    title: 'Mudéjar Patrimonio Mundial',
    subtitle: 'Ruta Mudéjar',
    icon: Icons.mosque_outlined,
    intro:
        'En 2001 la UNESCO incluyó el mudéjar de Zaragoza en el Patrimonio '
        'Mundial. Esta ruta reúne algunas de sus obras más destacadas en el '
        'casco histórico: la catedral de La Seo, las iglesias de la Magdalena '
        'y San Gil y la iglesia de San Pablo.',
    guidedDuration: 'unas 2 h 30 min',
    sourceUrl: '$_turismo/ver-y-hacer/paseo-mudejar',
    stops: [
      RouteStop.monument(
        'monumento-0',
        note: 'Interior y exterior, con la Parroquieta.',
      ),
      RouteStop.monument('monumento-12', note: 'Exterior.'),
      RouteStop.monument('monumento-15', note: 'Exterior.'),
      RouteStop.monument('monumento-8', note: 'Interior y exterior.'),
    ],
  ),
  CityRoute(
    id: 'renacentista',
    title: 'La Zaragoza del Renacimiento',
    subtitle: 'Paseo Renacentista',
    icon: Icons.castle_outlined,
    intro:
        'En el siglo XVI la ciudad renovó por completo su aspecto: el auge '
        'económico del reino de Aragón y de su capital se reflejó en grandes '
        'casas palacio. El paseo une el retablo mayor del Pilar, la Lonja y '
        'varios patios y portadas renacentistas del centro.',
    sourceUrl: '$_turismo/post/paseo-renacentista',
    stops: [
      RouteStop.monument('monumento-32', note: 'Retablo mayor.'),
      RouteStop.monument('monumento-18'),
      RouteStop.monument('monumento-25'),
      RouteStop.monument('monumento-29', note: 'El patio del museo.'),
      RouteStop.monument('monumento-27'),
      RouteStop.monument('monumento-28'),
      RouteStop.monument('monumento-20', note: 'El patio del palacio.'),
    ],
  ),
  CityRoute(
    id: 'goya',
    title: 'Zaragoza de Goya',
    subtitle: 'Tras los pasos del pintor',
    icon: Icons.palette_outlined,
    intro:
        'Francisco de Goya vivió en Zaragoza desde que tenía un mes hasta casi '
        'cumplir los 29 años. La ruta visita los lugares que conservan su '
        'huella en el centro: sus frescos en el Pilar, su monumento en la '
        'plaza y las obras expuestas en el Patio de la Infanta.',
    sourceUrl: '$_turismo/post/paseo-goya',
    stops: [
      RouteStop.monument(
        'monumento-32',
        note: 'Frescos de Goya: la bóveda del Coreto y la cúpula Regina Martyrum.',
      ),
      RouteStop.monument('monumento-91', note: 'En la plaza del Pilar.'),
      RouteStop.monument('monumento-28'),
    ],
  ),
  CityRoute(
    id: 'sitios',
    title: 'Los Sitios de Zaragoza',
    subtitle: '1808-1809',
    icon: Icons.flag_outlined,
    intro:
        'Entre mayo de 1808 y febrero de 1809 Zaragoza resistió los Sitios de '
        'las tropas napoleónicas, uno de los episodios más importantes de su '
        'historia. El recorrido pasa por los lugares que los recuerdan, desde '
        'el Puente de Piedra hasta la plaza de los Sitios.',
    guidedDuration: 'unas 2 horas',
    sourceUrl: '$_turismo/planifica-tu-viaje/los_sitios',
    stops: [
      RouteStop.monument('monumento-9'),
      RouteStop.monument('monumento-32'),
      RouteStop.monument('monumento-36', note: 'En la plaza de San Felipe.'),
      RouteStop.place('Plaza de España'),
      RouteStop.monument(
        'monumento-27',
        note: 'En la plaza de Santa Engracia.',
      ),
      RouteStop.monument('monumento-85', note: 'En la plaza de los Sitios.'),
    ],
  ),
];

/// Parada ya resuelta con su monumento (si lo hay en el listado).
class ResolvedStop {
  final RouteStop stop;
  final Monument? monument;

  const ResolvedStop(this.stop, this.monument);

  String get name => monument?.name ?? stop.name;

  bool get hasLocation => monument?.hasLocation ?? false;
}

List<ResolvedStop> resolveStops(CityRoute route, List<Monument> monuments) {
  final byId = {for (final m in monuments) m.id: m};
  return [
    for (final stop in route.stops)
      if (stop.monumentId == null || byId.containsKey(stop.monumentId))
        ResolvedStop(
          stop,
          stop.monumentId == null ? null : byId[stop.monumentId],
        ),
  ];
}

double _meters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Distancia aproximada a pie entre las paradas, en metros: la línea recta
/// entre ellas más un 30 % por las calles.
double walkingMeters(List<ResolvedStop> stops) {
  final located = [
    for (final s in stops)
      if (s.hasLocation) s.monument!,
  ];
  var total = 0.0;
  for (var i = 1; i < located.length; i++) {
    total += _meters(
      located[i - 1].lat!,
      located[i - 1].lng!,
      located[i].lat!,
      located[i].lng!,
    );
  }
  return total * 1.3;
}

/// «1,8 km · 25 min a pie» (a 4,5 km/h, sin contar las visitas).
String walkingLabel(double meters) {
  final minutes = (meters / 75).round().clamp(1, 600);
  final distance = meters < 1000
      ? '${(meters / 50).round() * 50} m'
      : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  return '$distance · $minutes min a pie';
}

/// La ruta completa a pie en Google Maps (enlace gratuito, sin clave).
Uri? routeMapsLink(List<ResolvedStop> stops) {
  final points = [
    for (final s in stops)
      if (s.hasLocation) '${s.monument!.lat},${s.monument!.lng}',
  ];
  if (points.length < 2) return null;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': points.first,
    'destination': points.last,
    if (points.length > 2)
      'waypoints': points.sublist(1, points.length - 1).join('|'),
    'travelmode': 'walking',
  });
}

// ---------------------------------------------------------------------------
// Interfaz
// ---------------------------------------------------------------------------

/// Pantalla de rutas: una tarjeta por ruta.
class RoutesScreen extends StatefulWidget {
  final MonumentsRepository repository;

  const RoutesScreen({
    super.key,
    this.repository = const HttpMonumentsRepository(),
  });

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  List<Monument> _monuments = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _monuments.isEmpty;
      _failed = false;
    });
    final cached = await widget.repository.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _monuments = cached;
        _loading = false;
      });
    }
    final fresh = await widget.repository.fetchFresh();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _monuments = fresh;
      _failed = fresh == null && _monuments.isEmpty;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const SkeletonList(count: 4);
    } else if (_failed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No se pudieron cargar las rutas. Comprueba tu conexión.',
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
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Recorridos a pie por la historia de la ciudad, basados en las '
              'rutas oficiales de Turismo de Zaragoza.',
              style: TextStyle(color: Brand.slate, height: 1.45),
            ),
          ),
          for (final route in cityRoutes) _routeCard(route),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Rutas')),
      body: body,
    );
  }

  Widget _routeCard(CityRoute route) {
    final stops = resolveStops(route, _monuments);
    final cover = stops
        .map((s) => s.monument)
        .whereType<Monument>()
        .firstWhere(
          (m) => m.image.isNotEmpty,
          orElse: () => const Monument(id: '', name: ''),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        height: 168,
        child: _RouteCard(
          route: route,
          stopsCount: stops.length,
          image: cover.image,
          width: double.infinity,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  RouteDetailScreen(route: route, monuments: _monuments),
            ),
          ),
        ),
      ),
    );
  }
}

/// Carrusel de rutas para la portada.
class RoutesCarousel extends StatelessWidget {
  final List<Monument> monuments;
  final double height;
  final double cardWidth;

  const RoutesCarousel({
    super.key,
    required this.monuments,
    this.height = 170,
    this.cardWidth = 230,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: cityRoutes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final route = cityRoutes[index];
          final stops = resolveStops(route, monuments);
          final cover = stops
              .map((s) => s.monument)
              .whereType<Monument>()
              .firstWhere(
                (m) => m.image.isNotEmpty,
                orElse: () => const Monument(id: '', name: ''),
              );
          return _RouteCard(
            route: route,
            stopsCount: stops.length,
            image: cover.image,
            width: cardWidth,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RouteDetailScreen(route: route, monuments: monuments),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  final CityRoute route;
  final int stopsCount;
  final String image;
  final double width;
  final VoidCallback onTap;

  const _RouteCard({
    required this.route,
    required this.stopsCount,
    required this.image,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Brand.navy, Brand.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(child: Icon(route.icon, size: 48, color: Colors.white38)),
    );
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Material(
          color: Brand.navy,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image.isEmpty)
                  fallback
                else
                  Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.2, 1.0],
                      colors: [Color(0x220B2D4A), Color(0xEE0B2D4A)],
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(route.icon, size: 14, color: Brand.coral),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'RUTA · $stopsCount PARADAS',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        route.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
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

class RouteDetailScreen extends StatelessWidget {
  final CityRoute route;
  final List<Monument> monuments;

  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.monuments,
  });

  Future<void> _launch(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    messenger.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stops = resolveStops(route, monuments);
    final meters = walkingMeters(stops);
    final mapsLink = routeMapsLink(stops);
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: Text(route.subtitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(
            route.title,
            style: const TextStyle(
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: Brand.navy,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                icon: Icons.place_outlined,
                text: '${stops.length} paradas',
              ),
              if (meters > 0)
                _Chip(
                  icon: Icons.directions_walk,
                  text: 'Aprox. ${walkingLabel(meters)}',
                ),
              if (route.guidedDuration.isNotEmpty)
                _Chip(
                  icon: Icons.schedule_outlined,
                  text: 'Visita guiada: ${route.guidedDuration}',
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            route.intro,
            style: const TextStyle(
              fontSize: 16,
              height: 1.6,
              color: Color(0xFF425B71),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Paradas',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Brand.navy,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < stops.length; i++)
            _StopTile(
              index: i + 1,
              isLast: i == stops.length - 1,
              stop: stops[i],
              onTap: stops[i].monument == null
                  ? () => _launch(
                      context,
                      Uri.https('www.google.com', '/maps/search/', {
                        'api': '1',
                        'query': '${stops[i].name}, Zaragoza',
                      }),
                    )
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MonumentDetailScreen(monument: stops[i].monument!),
                      ),
                    ),
            ),
          const SizedBox(height: 18),
          if (mapsLink != null)
            FilledButton.icon(
              onPressed: () => _launch(context, mapsLink),
              style: FilledButton.styleFrom(
                backgroundColor: Brand.navy,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Ver la ruta en Google Maps'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _launch(context, Uri.parse(route.sourceUrl)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.navy,
              side: const BorderSide(color: Brand.navy),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.language_rounded),
            label: const Text('Visita guiada oficial'),
          ),
          const SizedBox(height: 18),
          const Text(
            'Ruta e información: Turismo de Zaragoza (Ayuntamiento de Zaragoza). '
            'La distancia y el tiempo a pie son aproximados y no incluyen las '
            'visitas.',
            style: TextStyle(fontSize: 12, color: Color(0xFF738196)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Chip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Brand.coral),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Brand.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parada numerada con una línea que la une a la siguiente.
class _StopTile extends StatelessWidget {
  final int index;
  final bool isLast;
  final ResolvedStop stop;
  final VoidCallback onTap;

  const _StopTile({
    required this.index,
    required this.isLast,
    required this.stop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final monument = stop.monument;
    final detail = stop.stop.note.isNotEmpty
        ? stop.stop.note
        : (monument == null ? '' : monumentSubtitle(monument));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Brand.navy,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: Brand.skyLine)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Brand.line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stop.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Brand.navy,
                                ),
                              ),
                              if (detail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  detail,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: Brand.slate,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          monument == null
                              ? Icons.open_in_new
                              : Icons.chevron_right,
                          color: Brand.slate,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
