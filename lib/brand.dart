/// Identidad de marca de «Maña Zaragoza»: colores y tipografía.
library;

import 'package:flutter/material.dart';

class Brand {
  const Brand._();

  /// Nombre de la aplicación.
  static const String name = 'Maña Zaragoza';

  // Paleta elegida.
  static const Color navy = Color(0xFF0B2D4A);
  static const Color coral = Color(0xFFFF6B4A);
  static const Color sky = Color(0xFF4BB3E6);
  static const Color cream = Color(0xFFF7F6EF);

  // Tonos derivados de la paleta.
  /// Azul algo más claro, para degradados junto al azul principal.
  static const Color navyLight = Color(0xFF1A4F7A);

  /// Azul cielo muy suave, para fondos de tarjetas e indicadores.
  static const Color skyTint = Color(0xFFE4F3FB);

  /// Borde suave de las tarjetas sobre el fondo crema.
  static const Color line = Color(0xFFE3E0D3);

  /// Borde de las tarjetas de tono cielo.
  static const Color skyLine = Color(0xFFBEE2F4);

  /// Texto secundario.
  static const Color slate = Color(0xFF5B6B80);

  /// Tipografía de la marca.
  static const String fontFamily = 'Montserrat';
}
