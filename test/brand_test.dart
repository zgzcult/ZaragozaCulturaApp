import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/brand.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Marca', () {
    test('la paleta es la elegida', () {
      expect(Brand.navy, const Color(0xFF0B2D4A));
      expect(Brand.coral, const Color(0xFFFF6B4A));
      expect(Brand.sky, const Color(0xFF4BB3E6));
      expect(Brand.cream, const Color(0xFFF7F6EF));
    });

    test('el nombre es Maña Zaragoza en todas partes', () {
      expect(Brand.name, 'Maña Zaragoza');
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="Maña Zaragoza"'),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<string>Maña Zaragoza</string>'),
      );
      expect(
        File('backend/privacy.html').readAsStringSync(),
        contains('Maña Zaragoza'),
      );
      expect(
        File('backend/server.py').readAsStringSync(),
        contains('<h1>Maña Zaragoza</h1>'),
      );
    });

    test('el logo es un PNG con transparencia', () async {
      final data = await rootBundle.load('assets/brand/logo.png');
      expect(data.lengthInBytes, greaterThan(10000));
      // Firma PNG y tipo de color 6 (RGBA).
      expect(
        [for (var i = 0; i < 4; i++) data.getUint8(i)],
        [0x89, 0x50, 0x4E, 0x47],
      );
      expect(data.getUint8(25), 6);
    });

    test('la tipografía Montserrat está incluida con su licencia', () async {
      for (final name in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        final data = await rootBundle.load('assets/fonts/Montserrat-$name.ttf');
        expect(data.lengthInBytes, greaterThan(100000), reason: name);
      }
      final license = await rootBundle.loadString('assets/fonts/OFL.txt');
      expect(license, contains('SIL Open Font License'));
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Montserrat'));
      expect(pubspec, contains('weight: 700'));
      expect(Brand.fontFamily, 'Montserrat');
    });

    test('el icono de la aplicación usa el logo en Android e iOS', () {
      final res = 'android/app/src/main/res';
      for (final dir in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File('$res/mipmap-$dir/ic_launcher.png').existsSync(),
          isTrue,
          reason: dir,
        );
      }
      expect(
        File('$res/drawable-xxxhdpi/ic_launcher_foreground.png').existsSync(),
        isTrue,
      );
      expect(
        File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync(),
        contains('adaptive-icon'),
      );
      expect(
        File('$res/values/colors.xml').readAsStringSync(),
        contains('#F7F6EF'),
      );
      expect(
        File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
        ).existsSync(),
        isTrue,
      );
    });

    testWidgets('el tema usa la paleta: fondo crema, azul marino y coral', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ZaragozaCulturaApp());
      final theme = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(theme.scaffoldBackgroundColor, Brand.cream);
      expect(theme.colorScheme.primary, Brand.navy);
      expect(theme.colorScheme.secondary, Brand.coral);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('«Acerca de» ofrece las licencias de código abierto', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    expect(find.text('Licencias de código abierto'), findsOneWidget);
    expect(find.textContaining('CartoCiudad'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  test('Android muestra el logo sobre crema mientras arranca', () {
    final res = 'android/app/src/main/res';
    expect(
      File('$res/values/colors.xml').readAsStringSync(),
      contains('<color name="splash_background">#F7F6EF</color>'),
    );
    for (final v in ['drawable', 'drawable-v21']) {
      expect(
        File('$res/$v/launch_background.xml').readAsStringSync(),
        allOf(
          contains('@color/splash_background'),
          contains('@drawable/splash_logo'),
        ),
        reason: v,
      );
    }
    for (final v in ['values-v31', 'values-night-v31']) {
      expect(
        File('$res/$v/styles.xml').readAsStringSync(),
        allOf(
          contains('windowSplashScreenBackground'),
          contains('@drawable/splash_icon'),
        ),
        reason: v,
      );
    }
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File('$res/drawable-$d/splash_logo.png').existsSync(), isTrue);
      expect(File('$res/drawable-$d/splash_icon.png').existsSync(), isTrue);
    }
  });

  testWidgets('La aplicación arranca directamente en la pantalla principal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ZaragozaCulturaApp());
    // Sin animación previa: la pantalla principal está desde el primer frame.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Bienvenid@ a'), findsOneWidget);
    expect(find.textContaining('Maña Zaragoza'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
