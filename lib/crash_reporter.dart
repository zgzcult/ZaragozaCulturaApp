/// Informes de errores: si la app falla, envía a nuestro servidor un informe
/// técnico (mensaje de error, traza, versión de la app y del sistema) para
/// poder corregirlo. Sin identificadores del usuario ni del dispositivo.
///
/// Solo en la versión publicada (no en desarrollo ni en los tests) y solo si
/// el usuario no lo ha desactivado en Ajustes.
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';

const String _crashUrl = 'https://zaragoza-cultura-app.onrender.com/crash';
const String _enabledKey = 'crash_reports_enabled';

/// Envío del informe. Se puede sustituir en los tests.
typedef CrashSender = Future<void> Function(Map<String, String> report);

Future<void> _httpSender(Map<String, String> report) async {
  await http
      .post(
        Uri.parse(_crashUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(report),
      )
      .timeout(const Duration(seconds: 20));
}

class CrashReporter {
  CrashReporter({
    CrashSender sender = _httpSender,
    this.maxPerSession = 3,
    this.platform,
    this.osVersion,
  }) : _sender = sender;

  final CrashSender _sender;

  /// Tope de informes por sesión: un fallo en bucle no debe inundar el
  /// servidor ni gastar datos del usuario.
  final int maxPerSession;
  final String? platform;
  final String? osVersion;

  final Set<String> _seen = <String>{};
  int _sent = 0;

  /// ¿Están activados los informes? (Por defecto, sí.)
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  /// Datos del informe: solo técnicos.
  Map<String, String> buildReport(Object error, StackTrace? stack) {
    final text = error.toString();
    final trace = (stack ?? StackTrace.empty).toString();
    return {
      'error': text.length > 500 ? text.substring(0, 500) : text,
      'stack': trace.length > 6000 ? trace.substring(0, 6000) : trace,
      'appVersion': Brand.appVersion,
      'platform': platform ?? (kIsWeb ? 'web' : Platform.operatingSystem),
      'osVersion': osVersion ?? (kIsWeb ? '' : Platform.operatingSystemVersion),
    };
  }

  /// Envía el informe si procede. Nunca lanza: un fallo al informar no debe
  /// provocar otro error.
  Future<bool> report(Object error, StackTrace? stack) async {
    try {
      if (_sent >= maxPerSession) return false;
      final data = buildReport(error, stack);
      // El mismo fallo en el mismo sitio solo se informa una vez por sesión.
      final key = '${data['error']}|${data['stack']!.split('\n').first}';
      if (!_seen.add(key)) return false;
      if (!await isEnabled()) return false;
      _sent++;
      await _sender(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Engancha el informador a los errores de Flutter y de Dart. Solo en la
  /// versión publicada.
  static void install({CrashReporter? reporter, bool? force}) {
    if (!(force ?? kReleaseMode)) return;
    final instance = reporter ?? CrashReporter();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      instance.report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.report(error, stack);
      return false; // que el sistema lo trate igual que antes
    };
  }
}
