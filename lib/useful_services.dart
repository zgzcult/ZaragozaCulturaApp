/// «Servicios útiles»: farmacias de guardia, centros de salud públicos y
/// bibliotecas municipales. Las fuentes de los datos se citan en «Acerca de».
/// Sin mapas: cada lugar se abre en Google Maps por su dirección.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';
import 'event_classifier.dart';
import 'ui_kit.dart';

const String _servicesUrl =
    'https://zaragoza-cultura-app.onrender.com/services';
const String _servicesCacheKey = 'cached_services';

// ---------------------------------------------------------------------------
// Datos
// ---------------------------------------------------------------------------

class ServiceItem {
  final String id;
  final String name;
  final String address;
  final String phone;

  /// Número para llamar (solo cifras) o vacío.
  final String call;
  final String horario;

  /// Guardia de la farmacia, precio del aseo...
  final String info;

  /// Ficha oficial en zaragoza.es.
  final String url;

  const ServiceItem({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.call = '',
    this.horario = '',
    this.info = '',
    this.url = '',
  });

  static ServiceItem? fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] ?? '').toString().trim();
    final name = text('name');
    if (name.isEmpty) return null;
    return ServiceItem(
      id: text('id').isEmpty ? name : text('id'),
      name: name,
      address: text('address'),
      phone: text('phone'),
      call: text('call'),
      horario: text('horario'),
      info: text('info'),
      url: text('url'),
    );
  }
}

class ServiceGroup {
  final String id;
  final String title;
  final List<ServiceItem> items;

  /// El Ayuntamiento no respondió para este grupo.
  final bool failed;

  const ServiceGroup({
    required this.id,
    required this.title,
    this.items = const [],
    this.failed = false,
  });
}

List<ServiceGroup> parseServices(dynamic decoded) {
  final groups = <ServiceGroup>[];
  final list = decoded is Map ? decoded['groups'] : null;
  if (list is! List) return groups;
  for (final raw in list) {
    if (raw is! Map) continue;
    final items = <ServiceItem>[];
    final rawItems = raw['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is! Map) continue;
        final parsed = ServiceItem.fromJson(Map<String, dynamic>.from(item));
        if (parsed != null) items.add(parsed);
      }
    }
    groups.add(
      ServiceGroup(
        id: (raw['id'] ?? '').toString(),
        title: (raw['title'] ?? '').toString(),
        items: items,
        failed: raw['error'] == true,
      ),
    );
  }
  return groups;
}

/// Cómo llegar en Google Maps buscando por nombre y dirección: Google sitúa
/// la dirección por su cuenta (enlace gratuito, sin clave).
Uri serviceDirectionsLink(ServiceItem item) {
  final destination = [
    item.name,
    item.address,
    'Zaragoza',
  ].where((part) => part.trim().isNotEmpty).join(', ');
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
  });
}

List<ServiceItem> searchServices(List<ServiceItem> items, String query) {
  final words = normalizeForSearch(query)
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return items;
  return items.where((item) {
    final haystack = normalizeForSearch('${item.name} ${item.address}');
    return words.every(haystack.contains);
  }).toList();
}

abstract class ServicesRepository {
  const ServicesRepository();

  Future<List<ServiceGroup>> loadCached();

  /// Descarga del servidor; null si no se pudo.
  Future<List<ServiceGroup>?> fetchFresh();
}

class HttpServicesRepository extends ServicesRepository {
  const HttpServicesRepository();

  @override
  Future<List<ServiceGroup>> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_servicesCacheKey);
      return raw == null ? const [] : parseServices(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<ServiceGroup>?> fetchFresh() async {
    try {
      final response = await http
          .get(Uri.parse(_servicesUrl))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final groups = parseServices(jsonDecode(body));
      if (groups.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_servicesCacheKey, body);
      return groups;
    } catch (_) {
      return null;
    }
  }
}

Future<void> _launch(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  messenger.showSnackBar(
    const SnackBar(content: Text('No se pudo abrir el enlace.')),
  );
}

IconData _groupIcon(String id) => switch (id) {
  'farmacias-guardia' => Icons.local_pharmacy_outlined,
  'centros-salud' => Icons.medical_services_outlined,
  'bibliotecas' => Icons.local_library_outlined,
  _ => Icons.info_outline,
};

Color _groupColor(String id) => switch (id) {
  'farmacias-guardia' => const Color(0xFF2E9E6A),
  'centros-salud' => Brand.coral,
  'bibliotecas' => Brand.navyLight,
  _ => Brand.sky,
};

// ---------------------------------------------------------------------------
// Pantalla principal de servicios
// ---------------------------------------------------------------------------

class UsefulServicesScreen extends StatefulWidget {
  final ServicesRepository repository;

  const UsefulServicesScreen({
    super.key,
    this.repository = const HttpServicesRepository(),
  });

  @override
  State<UsefulServicesScreen> createState() => _UsefulServicesScreenState();
}

class _UsefulServicesScreenState extends State<UsefulServicesScreen> {
  List<ServiceGroup> _groups = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _groups.isEmpty;
      _failed = false;
    });
    final cached = await widget.repository.loadCached();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _groups = cached;
        _loading = false;
      });
    }
    final fresh = await widget.repository.fetchFresh();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _groups = fresh;
      _failed = fresh == null && _groups.isEmpty;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Servicios útiles')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const _SectionLabel('EMERGENCIAS'),
          const SizedBox(height: 10),
          const Row(
            children: [
              _EmergencyButton(number: '112', label: 'Emergencias'),
              SizedBox(width: 10),
              _EmergencyButton(number: '092', label: 'Policía Local'),
              SizedBox(width: 10),
              _EmergencyButton(number: '091', label: 'Policía Nacional'),
            ],
          ),
          const SizedBox(height: 26),
          const _SectionLabel('SERVICIOS'),
          const SizedBox(height: 10),
          if (_loading)
            Shimmer(
              child: Column(
                children: [
                  for (var i = 0; i < 5; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: SkeletonBox(height: 74, radius: 20),
                    ),
                ],
              ),
            )
          else if (_failed)
            Column(
              children: [
                const Text(
                  'No se pudieron cargar los servicios. Comprueba tu conexión.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.slate, height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Reintentar')),
              ],
            )
          else ...[
            for (final group in _groups) ...[
              _GroupTile(
                icon: _groupIcon(group.id),
                color: _groupColor(group.id),
                title: group.title,
                subtitle: group.failed && group.items.isEmpty
                    ? 'No disponible ahora mismo'
                    : group.id == 'farmacias-guardia'
                    ? '${group.items.length} abiertas hoy'
                    : group.id == 'centros-salud'
                    ? '${group.items.length} centros'
                    : group.id == 'bibliotecas'
                    ? '${group.items.length} bibliotecas'
                    : '${group.items.length} lugares',
                onTap: group.items.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ServiceGroupScreen(group: group),
                        ),
                      ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 2.5,
        fontWeight: FontWeight.w700,
        color: Brand.slate,
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  final String number;
  final String label;

  const _EmergencyButton({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: 'Llamar al $number, $label',
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _launch(context, Uri(scheme: 'tel', path: number)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Brand.line),
              ),
              child: Column(
                children: [
                  Text(
                    number,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Brand.coral,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    textAlign: TextAlign.center,
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
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _GroupTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Brand.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Brand.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Brand.slate,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right, color: Brand.slate),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista de un grupo
// ---------------------------------------------------------------------------

class ServiceGroupScreen extends StatefulWidget {
  final ServiceGroup group;

  const ServiceGroupScreen({super.key, required this.group});

  @override
  State<ServiceGroupScreen> createState() => _ServiceGroupScreenState();
}

class _ServiceGroupScreenState extends State<ServiceGroupScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final shown = searchServices(group.items, _query);
    final isPharmacy = group.id == 'farmacias-guardia';
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: Text(group.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          if (isPharmacy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Farmacias de guardia de hoy.',
                style: TextStyle(color: Brand.slate, height: 1.4),
              ),
            )
          else if (group.items.length > 6)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o calle',
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
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No hay resultados con esa búsqueda.',
                  style: TextStyle(color: Brand.slate),
                ),
              ),
            ),
          for (final item in shown)
            ServiceCard(
              item: item,
              color: _groupColor(group.id),
              horarioLabel: isPharmacy ? 'Horario habitual' : null,
            ),
        ],
      ),
    );
  }
}

class ServiceCard extends StatelessWidget {
  final ServiceItem item;
  final Color color;

  /// Rótulo del horario cuando hace falta distinguirlo de otro (en las
  /// farmacias de guardia, el horario de guardia va aparte en el recuadro de
  /// color y este es el habitual).
  final String? horarioLabel;

  const ServiceCard({
    super.key,
    required this.item,
    this.color = Brand.navy,
    this.horarioLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Brand.navy,
                  ),
                ),
                if (item.info.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.info,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: color == Brand.sky ? Brand.navy : color,
                      ),
                    ),
                  ),
                ],
                if (item.address.isNotEmpty)
                  _Row(icon: Icons.location_on_outlined, text: item.address),
                if (item.phone.isNotEmpty)
                  _Row(icon: Icons.phone_outlined, text: item.phone),
                if (item.horario.isNotEmpty)
                  _Row(
                    icon: Icons.schedule_outlined,
                    text: horarioLabel == null
                        ? item.horario
                        : '$horarioLabel:\n${item.horario}',
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Brand.line),
          Row(
            children: [
              if (item.call.isNotEmpty)
                _CardAction(
                  icon: Icons.call_outlined,
                  label: 'Llamar',
                  onTap: () =>
                      _launch(context, Uri(scheme: 'tel', path: item.call)),
                ),
              if (item.address.isNotEmpty)
                _CardAction(
                  icon: Icons.directions_outlined,
                  label: 'Cómo llegar',
                  onTap: () => _launch(context, serviceDirectionsLink(item)),
                ),
              if (item.url.isNotEmpty)
                _CardAction(
                  icon: Icons.language_rounded,
                  label: 'Ficha',
                  onTap: () => _launch(context, Uri.parse(item.url)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Row({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF48617A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF28415E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Brand.navy),
              const SizedBox(width: 6),
              // Flexible: con tres botones en un móvil estrecho el texto se
              // recorta antes que desbordar.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Brand.navy,
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
