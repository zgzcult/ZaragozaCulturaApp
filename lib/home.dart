/// Pantalla principal: Actividades, Restaurantes y Sugerencia del día.
library;

import 'package:flutter/material.dart';

import 'day_suggestion.dart';
import 'main.dart';
import 'nearby.dart';
import 'restaurants.dart';

class HomeScreen extends StatelessWidget {
  final ZaragozaEventsRepository repository;
  final LocationService locationService;
  final PlacesRepository placesRepository;
  final WeatherSource weatherSource;

  const HomeScreen({
    super.key,
    this.repository = const ZaragozaEventsRepository(),
    this.locationService = const DeviceLocationService(),
    this.placesRepository = const HttpPlacesRepository(),
    this.weatherSource = const HttpWeatherSource(),
  });

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Zaragoza Cultura',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF10243E),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Qué hacer y dónde comer en Zaragoza',
                style: TextStyle(fontSize: 16, color: Color(0xFF738196)),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: _HomeButton(
                        icon: Icons.calendar_month,
                        color: const Color(0xFF1E5F74),
                        title: 'Actividades',
                        subtitle: 'Agenda por días, cerca de ti, buscador y favoritos',
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
                      child: _HomeButton(
                        icon: Icons.restaurant,
                        color: const Color(0xFFB4561B),
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
                      child: _HomeButton(
                        icon: Icons.wb_twilight,
                        color: const Color(0xFF7B5FBF),
                        title: 'Sugerencia del día',
                        subtitle: 'Qué hacer hoy, según el tiempo',
                        onTap: () => _open(
                          context,
                          SuggestionOfDayScreen(
                            repository: repository,
                            weatherSource: weatherSource,
                          ),
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

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeButton({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color,
                Color.lerp(color, const Color(0xFF10243E), 0.45)!,
              ],
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.92)),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
