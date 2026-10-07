/// «Cine»: los cines de Zaragoza con enlace a la cartelera de cada uno.
///
/// La app no muestra las películas ni los horarios: los publica cada cine en
/// su web, que es a donde lleva el botón «Ver cartelera».
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand.dart';

class Cinema {
  final String name;
  final String address;

  /// Página del cine con su cartelera y horarios.
  final String url;

  /// Detalle breve (salas, tipo de cine).
  final String note;

  const Cinema({
    required this.name,
    required this.address,
    required this.url,
    this.note = '',
  });
}

/// Cines de Zaragoza capital con programación (comprobados el 7-10-2026).
const List<Cinema> zaragozaCinemas = [
  Cinema(
    name: 'Cines Palafox',
    address: 'Paseo de la Independencia, 12, 50004 Zaragoza',
    url: 'https://www.cinespalafox.com/cine/cinespalafox',
  ),
  Cinema(
    name: 'Cine Cervantes',
    address: 'Calle del Marqués de Casa Jiménez, 2, 50004 Zaragoza',
    url: 'https://www.cinespalafox.com/cine/cervantes',
  ),
  Cinema(
    name: 'Cines Aragonia',
    address: 'Avenida Juan Carlos I, 44, 50009 Zaragoza',
    url: 'https://www.cinespalafox.com/cine/cinesaragonia',
    note: 'Centro comercial Aragonia',
  ),
  Cinema(
    name: 'Cinesa GranCasa',
    address: 'Calle de María Zambrano, 35, 50018 Zaragoza',
    url: 'https://www.cinesa.es/cines/grancasa/',
    note: 'Centro comercial GranCasa',
  ),
  Cinema(
    name: 'Cinesa Puerto Venecia',
    address: 'Avenida Puerto Venecia, 3, 50021 Zaragoza',
    url: 'https://www.cinesa.es/cines/puerto-venecia/',
    note: 'Centro comercial Puerto Venecia',
  ),
  Cinema(
    name: 'Artesiete La Torre',
    address: 'Autovía de Logroño, 50011 Zaragoza',
    url: 'https://latorre.artesiete.es/Cine/21/artesiete-la-torre',
    note: 'La Torre Outlet',
  ),
  Cinema(
    name: 'Filmoteca de Zaragoza',
    address: 'Plaza de San Carlos, 4, 50001 Zaragoza',
    url: 'https://filmotecazaragoza.com/',
    note: 'Cine de autor y ciclos (municipal)',
  ),
];

/// Cómo llegar al cine, buscando por nombre y dirección en Google Maps.
Uri cinemaDirectionsLink(Cinema cinema) => Uri.https(
  'www.google.com',
  '/maps/dir/',
  {'api': '1', 'destination': '${cinema.name}, ${cinema.address}'},
);

class CinemasScreen extends StatelessWidget {
  const CinemasScreen({super.key});

  static Future<void> _launch(BuildContext context, Uri uri) async {
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
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Cine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Elige tu cine y consulta la cartelera y los horarios en su web.',
              style: TextStyle(color: Brand.slate, height: 1.45),
            ),
          ),
          for (final cinema in zaragozaCinemas)
            _CinemaCard(
              cinema: cinema,
              onListings: () => _launch(context, Uri.parse(cinema.url)),
              onDirections: () =>
                  _launch(context, cinemaDirectionsLink(cinema)),
            ),
        ],
      ),
    );
  }
}

class _CinemaCard extends StatelessWidget {
  final Cinema cinema;
  final VoidCallback onListings;
  final VoidCallback onDirections;

  const _CinemaCard({
    required this.cinema,
    required this.onListings,
    required this.onDirections,
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Brand.skyTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.movie_outlined, color: Brand.navy),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cinema.name,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: Brand.navy,
                        ),
                      ),
                      if (cinema.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          cinema.note,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Brand.slate,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        cinema.address,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Color(0xFF28415E),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Brand.line),
          Row(
            children: [
              _Action(
                icon: Icons.local_movies_outlined,
                label: 'Ver cartelera',
                onTap: onListings,
              ),
              _Action(
                icon: Icons.directions_outlined,
                label: 'Cómo llegar',
                onTap: onDirections,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Action({required this.icon, required this.label, required this.onTap});

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
