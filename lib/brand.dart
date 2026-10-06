/// Identidad de marca de «Maña Zaragoza»: colores y tipografía.
library;

import 'package:flutter/material.dart';

class Brand {
  const Brand._();

  /// Nombre de la aplicación.
  static const String name = 'Maña Zaragoza';

  /// Versión de la aplicación. Debe coincidir con `version:` de pubspec.yaml
  /// (un test lo comprueba); se incluye en los informes de errores.
  static const String appVersion = '1.0.0+1';

  /// Dirección de nuestro servidor.
  static const String serverUrl = 'https://zaragoza-cultura-app.onrender.com';

  /// Esquema propio con el que un enlace abre una actividad dentro de la app.
  static const String linkScheme = 'manazaragoza';

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

  // Versiones oscuras de los colores de marca, para cuando van como TEXTO o
  // icono sobre fondo claro: el coral y el azul cielo originales no alcanzan
  // el contraste mínimo de lectura (4,5:1) y quedan para fondos y adornos.
  /// Coral para texto e iconos sobre crema o blanco (4,7:1 sobre crema).
  static const Color coralDeep = Color(0xFFD62700);

  /// Azul cielo para texto e iconos sobre crema o blanco (4,7:1).
  static const Color skyDeep = Color(0xFF1776A5);

  /// Verde de las farmacias, legible sobre crema o blanco (4,6:1).
  static const Color green = Color(0xFF257E55);

  /// Tipografía de la marca.
  static const String fontFamily = 'Montserrat';
}
