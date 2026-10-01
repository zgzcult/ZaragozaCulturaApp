/// Pantalla principal de Maña Zaragoza: Actividades, Restaurantes y la
/// sugerencia del día.
library;

import 'package:flutter/material.dart';

import 'brand.dart';
import 'day_suggestion.dart';
import 'main.dart';
import 'nearby.dart';
import 'restaurants.dart';

class HomeScreen extends StatelessWidget {
  final ZaragozaEventsRepository repository;
  final LocationService locationService;
  final PlacesRepository placesRepository;

  const HomeScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.locationService = const DeviceLocationService(),
    this.placesRepository = const HttpPlacesRepository(),
  });

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset(
                    'assets/brand/logo.png',
                    width: 62,
                    filterQuality: FilterQuality.high,
                    semanticLabel: Brand.name,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 62, height: 62),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Bienvenid@ a\n',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                              color: Brand.slate,
                            ),
                          ),
                          TextSpan(
                            text: 'Maña Zaragoza',
                            style: TextStyle(
                              fontSize: 27,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: Brand.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: 46,
                height: 3,
                decoration: BoxDecoration(
                  color: Brand.coral,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _HomeCard(
                        image: 'assets/home/actividades.jpg',
                        icon: Icons.calendar_month_outlined,
                        accent: Brand.sky,
                        label: 'AGENDA',
                        title: 'Actividades',
                        subtitle: 'Por días, cerca de ti, buscador y favoritos',
                        onTap: () => _open(
                          context,
                          AgendaScreen(
                            repository: repository,
                            locationService: locationService,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _HomeCard(
                        image: 'assets/home/restaurantes.jpg',
                        icon: Icons.restaurant_outlined,
                        accent: Brand.coral,
                        label: 'GASTRONOMÍA',
                        title: 'Restaurantes',
                        subtitle: 'Dónde comer, en el mapa',
                        onTap: () => _open(
                          context,
                          RestaurantsScreen(
                            repository: placesRepository,
                            locationService: locationService,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _HomeCard(
                        image: 'assets/home/sugerencias.jpg',
                        icon: Icons.auto_awesome_outlined,
                        accent: Brand.navy,
                        label: 'PARA HOY',
                        title: 'Sugerencia del día',
                        subtitle: 'Hoy te recomendamos esto',
                        onTap: () => _open(
                          context,
                          SuggestionOfDayScreen(repository: repository),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con foto de fondo, banda de color a la izquierda y un círculo con
/// flecha que invita a entrar.
class _HomeCard extends StatelessWidget {
  final String image;
  final IconData icon;
  final Color accent;
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.image,
    required this.icon,
    required this.accent,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(26);
    return Semantics(
      button: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x240B2D4A),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Brand.skyTint,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    image,
                    fit: BoxFit.cover,
                    cacheWidth: 1000,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Brand.skyTint),
                  ),
                  // Velo ligero a la izquierda, para que el texto se lea bien.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x8CFFFFFF),
                          Color(0x33FFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 6,
                    child: ColoredBox(color: accent),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 18, 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 16, color: Brand.navy),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 2.5,
                                      fontWeight: FontWeight.w700,
                                      color: Brand.navy,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 25,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  color: Brand.navy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.3,
                                  color: Brand.slate,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(
                              color: Brand.navy,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x330B2D4A),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_forward,
                              size: 20,
                              color: Colors.white,
                            ),
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
      ),
    );
  }
}
