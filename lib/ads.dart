/// Preparación para mostrar publicidad.
///
/// Todavía no hay plataforma de anuncios elegida, así que aquí solo se
/// reserva el hueco en las listas. Con [AdConfig.enabled] en `false` la app se
/// ve exactamente igual que sin publicidad. Cuando se elija plataforma (por
/// ejemplo AdMob) solo hay que activarlo y dibujar el anuncio en [AdSlot].
library;

import 'package:flutter/material.dart';

class AdConfig {
  static const bool enabled = false;

  /// Un anuncio después de cada este número de actividades.
  static const int everyNCards = 5;
}

/// Número total de elementos de la lista, contando los huecos de anuncio.
int withAds(int eventCount) {
  if (!AdConfig.enabled) return eventCount;
  return eventCount + eventCount ~/ AdConfig.everyNCards;
}

/// ¿El elemento [index] de la lista es un hueco de anuncio?
bool isAdIndex(int index) {
  if (!AdConfig.enabled) return false;
  return (index + 1) % (AdConfig.everyNCards + 1) == 0;
}

/// Posición de la actividad que corresponde al elemento [index] de la lista.
int eventIndexFor(int index) {
  if (!AdConfig.enabled) return index;
  return index - (index + 1) ~/ (AdConfig.everyNCards + 1);
}

/// Hueco donde irá un anuncio. Sin publicidad activa no ocupa espacio.
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.enabled) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'Publicidad',
        style: TextStyle(fontSize: 12, color: Color(0xFF738196)),
      ),
    );
  }
}
