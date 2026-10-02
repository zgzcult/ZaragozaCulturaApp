/// «Monumentos y museos»: el patrimonio de Zaragoza con los textos, horarios,
/// precios y fotos oficiales del Ayuntamiento.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'event_classifier.dart';
import 'routes.dart';
import 'ui_kit.dart';

const String _monumentsUrl =
    'https://zaragoza-cultura-app.onrender.com/places?type=monumento';
const String _monumentsCacheKey = 'cached_places_monumento';

// ---------------------------------------------------------------------------
// Datos
// ---------------------------------------------------------------------------

class Monument {
  final String id;
  final String name;
  final String description;
  final String horario;
  final String price;
  final String datacion;
  final String estilo;

  /// Grupos de estilo para los filtros: «Romano», «Mudéjar», «Barroco»...
  final List<String> styles;
  final bool museum;

  /// Marcado como imprescindible por el Ayuntamiento.
  final bool top;
  final String image;
  final String address;
  final String phone;

  /// Ficha oficial en zaragoza.es.
  final String url;
  final double? lat;
  final double? lng;

  const Monument({
    required this.id,
    required this.name,
    this.description = '',
    this.horario = '',
    this.price = '',
    this.datacion = '',
    this.estilo = '',
    this.styles = const [],
    this.museum = false,
    this.top = false,
    this.image = '',
    this.address = '',
    this.phone = '',
    this.url = '',
    this.lat,
    this.lng,
  });

  bool get hasLocation => lat != null && lng != null;

  static Monument? fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    String text(String key) => (json[key] ?? '').toString().trim();
    final styles = json['styles'];
    return Monument(
      id: (json['id'] ?? name).toString(),
      name: name,
      description: text('description'),
      horario: text('horario'),
      price: text('price'),
      datacion: text('datacion'),
      estilo: text('estilo'),
      styles: styles is List
          ? [for (final s in styles) s.toString()]
          : const <String>[],
      museum: json['museum'] == true,
      top: json['top'] == true,
      image: text('image'),
      address: text('address'),
      phone: text('phone'),
      url: text('url'),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
    );
  }
}

List<Monument> parseMonuments(dynamic decoded) {
  final list = <Monument>[];
  if (decoded is! List) return list;
  for (final item in decoded) {
    if (item is! Map) continue;
    final monument = Monument.fromJson(Map<String, dynamic>.from(item));
    if (monument != null) list.add(monument);
  }
  return list;
}

/// Orden de los filtros de estilo, de lo más antiguo a lo más reciente.
const List<String> monumentStyleOrder = [
  'Romano',
  'Medieval',
  'Mudéjar',
  'Renacentista',
  'Barroco',
  'Neoclásico',
  'Modernista',
  'Contemporáneo',
  'Actual',
  'Naturaleza',
];

const String filterAll = 'Todos';
const String filterTop = 'Imprescindibles';
const String filterMuseums = 'Museos';

/// Filtros disponibles: los fijos y los estilos que tengan algún monumento.
List<String> monumentFilters(List<Monument> monuments) {
  final present = {for (final m in monuments) ...m.styles};
  return [
    filterAll,
    if (monuments.any((m) => m.top)) filterTop,
    if (monuments.any((m) => m.museum)) filterMuseums,
    for (final style in monumentStyleOrder)
      if (present.contains(style)) style,
  ];
}

/// Monumentos que cumplen el filtro y la búsqueda (por nombre, dirección o
/// estilo). Primero los imprescindibles y después por orden alfabético.
List<Monument> filterMonuments(
  List<Monument> monuments, {
  String filter = filterAll,
  String query = '',
}) {
  final words = normalizeForSearch(query)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  final result = monuments.where((m) {
    final matchesFilter = switch (filter) {
      filterAll => true,
      filterTop => m.top,
      filterMuseums => m.museum,
      _ => m.styles.contains(filter),
    };
    if (!matchesFilter) return false;
    if (words.isEmpty) return true;
    final haystack = normalizeForSearch(
      '${m.name} ${m.address} ${m.estilo} ${m.styles.join(' ')}',
    );
    return words.every(haystack.contains);
  }).toList();
  result.sort((a, b) {
    if (a.top != b.top) return a.top ? -1 : 1;
    return normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name));
  });
  return result;
}

/// Ruta a pie hasta el monumento en Google Maps (enlace gratuito, sin clave).
Uri directionsLink(Monument monument) {
  final destination = monument.hasLocation
      ? '${monument.lat},${monument.lng}'
      : '${monument.name} ${monument.address} Zaragoza';
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
    'travelmode': 'walking',
  });
}

/// Primer teléfono del texto («976 72 12 21 - Reservas 976 72 60 75»), solo
/// con cifras, o null si no hay.
String? firstPhoneNumber(String text) {
  final match = RegExp(r'(\+?\d[\d ]{7,}\d)').firstMatch(text);
  if (match == null) return null;
  final digits = match.group(1)!.replaceAll(' ', '');
  return digits.length >= 9 ? digits : null;
}

/// Carga de monumentos. Se puede sustituir en los tests.
abstract class MonumentsRepository {
  const MonumentsRepository();

  Future<List<Monument>> loadCached();

  /// Descarga del servidor; null si no se pudo.
  Future<List<Monument>?> fetchFresh();
}

class HttpMonumentsRepository extends MonumentsRepository {
  const HttpMonumentsRepository();

  @override
  Future<List<Monument>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_monumentsCacheKey);
      return raw == null ? const <Monument>[] : parseMonuments(jsonDecode(raw));
    } catch (_) {
      return const <Monument>[];
    }
  }

  @override
  Future<List<Monument>?> fetchFresh() async {
    try {
      final response = await http
          .get(Uri.parse(_monumentsUrl))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final monuments = parseMonuments(jsonDecode(body));
      if (monuments.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_monumentsCacheKey, body);
      return monuments;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Listado
// ---------------------------------------------------------------------------

class MonumentsScreen extends StatefulWidget {
  final MonumentsRepository repository;

  const MonumentsScreen({
    super.key,
    this.repository = const HttpMonumentsRepository(),
  });

  @override
  State<MonumentsScreen> createState() => _MonumentsScreenState();
}

class _MonumentsScreenState extends State<MonumentsScreen> {
  List<Monument> _all = const [];
  String _filter = filterAll;
  String _query = '';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _all.isEmpty;
      _failed = false;
    });
    final cached = await widget.repository.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _all = cached;
        _loading = false;
      });
    }
    final fresh = await widget.repository.fetchFresh();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _all = fresh;
      _failed = fresh == null && _all.isEmpty;
      _loading = false;
    });
  }

  void _open(Monument monument) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonumentDetailScreen(monument: monument),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                'No se pudieron cargar los monumentos. Comprueba tu conexión.',
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
      final filters = monumentFilters(_all);
      final shown = filterMonuments(_all, filter: _filter, query: _query);
      body = CustomScrollView(
        slivers: [
          if (_query.isEmpty && _filter == filterAll)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
                      child: Text(
                        'Rutas para descubrir Zaragoza',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Brand.navy,
                        ),
                      ),
                    ),
                    RoutesCarousel(monuments: _all),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar monumento, museo o estilo',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = filters[index];
                  final selected = filter == _filter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = filter),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Brand.navy,
                    ),
                    selectedColor: Brand.navy,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: selected ? Brand.navy : Brand.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
              child: Text(
                shown.length == 1 ? '1 lugar' : '${shown.length} lugares',
                style: const TextStyle(
                  color: Brand.slate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (shown.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No hay resultados con esa búsqueda.',
                  style: TextStyle(color: Brand.slate),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) => _MonumentCard(
                  monument: shown[index],
                  onTap: () => _open(shown[index]),
                ),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Monumentos y museos')),
      body: body,
    );
  }
}

/// Foto del monumento, o un fondo de la marca con un icono si no hay o falla.
class _MonumentImage extends StatelessWidget {
  final Monument monument;
  final double iconSize;

  const _MonumentImage({required this.monument, this.iconSize = 56});

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Brand.navy, Brand.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          monument.museum
              ? Icons.museum_outlined
              : Icons.account_balance_outlined,
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
    if (monument.image.isEmpty) return placeholder;
    return Image.network(
      monument.image,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Shimmer(
              child: SkeletonBox(height: double.infinity, radius: 0),
            ),
    );
  }
}

/// Época y estilo en una línea: «Siglo XVI · Renacentista».
String monumentSubtitle(Monument monument) {
  return [
    if (monument.datacion.isNotEmpty) monument.datacion,
    if (monument.styles.isNotEmpty) monument.styles.join(', '),
  ].join(' · ');
}

class _MonumentCard extends StatelessWidget {
  final Monument monument;
  final VoidCallback onTap;

  const _MonumentCard({required this.monument, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitle = monumentSubtitle(monument);
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
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 190,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'monument-${monument.id}',
                    child: _MonumentImage(monument: monument),
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
                  if (monument.top || monument.museum)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Row(
                        children: [
                          if (monument.top)
                            const _Badge(
                              icon: Icons.star_rounded,
                              label: 'Imprescindible',
                              color: Brand.coral,
                            ),
                          if (monument.top && monument.museum)
                            const SizedBox(width: 6),
                          if (monument.museum)
                            const _Badge(
                              icon: Icons.museum_outlined,
                              label: 'Museo',
                              color: Brand.navy,
                            ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Text(
                      monument.name,
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
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle.isNotEmpty) ...[
                    _Line(icon: Icons.history_edu_outlined, text: subtitle),
                    const SizedBox(height: 6),
                  ],
                  if (monument.address.isNotEmpty)
                    _Line(
                      icon: Icons.location_on_outlined,
                      text: monument.address,
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

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

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
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Line({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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

// ---------------------------------------------------------------------------
// Ficha
// ---------------------------------------------------------------------------

class MonumentDetailScreen extends StatefulWidget {
  final Monument monument;

  const MonumentDetailScreen({super.key, required this.monument});

  @override
  State<MonumentDetailScreen> createState() => _MonumentDetailScreenState();
}

class _MonumentDetailScreenState extends State<MonumentDetailScreen> {
  static const double _headerHeight = 300;
  final ScrollController _scroll = ScrollController();
  bool _collapsed = false;
  bool _expanded = false;

  Monument get monument => widget.monument;

  @override
  void initState() {
    super.initState();
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

  Future<void> _launch(Uri uri) async {
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
    final phone = firstPhoneNumber(monument.phone);
    final description = monument.description;
    final isLong = description.length > 600;
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
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _collapsed
                  ? Text(
                      monument.name,
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
              background: Hero(
                tag: 'monument-${monument.id}',
                child: _MonumentImage(monument: monument, iconSize: 84),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (monument.top)
                        const _Badge(
                          icon: Icons.star_rounded,
                          label: 'Imprescindible',
                          color: Brand.coral,
                        ),
                      if (monument.museum)
                        const _Badge(
                          icon: Icons.museum_outlined,
                          label: 'Museo',
                          color: Brand.navy,
                        ),
                      for (final style in monument.styles)
                        _Badge(
                          icon: Icons.architecture,
                          label: style,
                          color: Brand.navyLight,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    monument.name,
                    style: const TextStyle(
                      color: Brand.navy,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  if (monument.datacion.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.history_edu_outlined,
                          color: Brand.coral,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            monument.datacion,
                            style: const TextStyle(
                              color: Brand.slate,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (monument.address.isNotEmpty ||
                      monument.phone.isNotEmpty) ...[
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
                          if (monument.address.isNotEmpty)
                            _Line(
                              icon: Icons.location_on_rounded,
                              text: monument.address,
                            ),
                          if (monument.address.isNotEmpty &&
                              monument.phone.isNotEmpty)
                            const SizedBox(height: 10),
                          if (monument.phone.isNotEmpty)
                            _Line(
                              icon: Icons.phone_outlined,
                              text: monument.phone,
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const _SectionTitle('Descripción'),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      alignment: Alignment.topCenter,
                      child: Text(
                        description,
                        maxLines: isLong && !_expanded ? 9 : null,
                        overflow: isLong && !_expanded
                            ? TextOverflow.ellipsis
                            : null,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: Color(0xFF425B71),
                        ),
                      ),
                    ),
                    if (isLong)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        style: TextButton.styleFrom(
                          foregroundColor: Brand.coral,
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(_expanded ? 'Leer menos' : 'Leer más'),
                      ),
                  ],
                  if (monument.horario.isNotEmpty) ...[
                    const _SectionTitle('Horario'),
                    _InfoBox(
                      icon: Icons.schedule_outlined,
                      text: monument.horario,
                    ),
                  ],
                  if (monument.price.isNotEmpty) ...[
                    const _SectionTitle('Precio'),
                    _InfoBox(
                      icon: Icons.confirmation_number_outlined,
                      text: monument.price,
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text(
                    'Texto, horarios e imagen: Ayuntamiento de Zaragoza. '
                    'Consulta la ficha oficial antes de tu visita.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF738196)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                _BottomAction(
                  icon: Icons.directions_walk,
                  label: 'Cómo llegar',
                  onTap: () => _launch(directionsLink(monument)),
                ),
                if (phone != null)
                  _BottomAction(
                    icon: Icons.phone_outlined,
                    label: 'Llamar',
                    onTap: () => _launch(Uri(scheme: 'tel', path: phone)),
                  ),
                if (monument.url.isNotEmpty)
                  _BottomAction(
                    icon: Icons.language_rounded,
                    label: 'Más información',
                    onTap: () => _launch(Uri.parse(monument.url)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Brand.navy,
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoBox({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.skyTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Brand.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Color(0xFF28415E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Brand.navy),
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
    );
  }
}
