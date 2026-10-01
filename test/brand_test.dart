import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/brand.dart';
import 'package:zaragoza_cultura_app/home.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/splash.dart';

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

  group('Bienvenida animada', () {
    Widget app({Duration duration = const Duration(milliseconds: 2900)}) =>
        MaterialApp(
          home: SplashScreen(
            duration: duration,
            next: (_) => const Scaffold(body: Text('PANTALLA PRINCIPAL')),
          ),
        );

    testWidgets('muestra el nombre y pasa sola a la pantalla principal', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 1800));
      expect(find.text('Maña'), findsOneWidget);
      expect(find.text('ZARAGOZA'), findsOneWidget);
      expect(find.text('PANTALLA PRINCIPAL'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('PANTALLA PRINCIPAL'), findsOneWidget);
      expect(find.text('Maña'), findsNothing);
    });

    testWidgets('el logo aparece desvanecido y crece al empezar', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 50));
      final early = tester.widget<Opacity>(
        find
            .ancestor(of: find.byType(Image), matching: find.byType(Opacity))
            .first,
      );
      expect(early.opacity, lessThan(0.5));
      await tester.pump(const Duration(milliseconds: 1200));
      final later = tester.widget<Opacity>(
        find
            .ancestor(of: find.byType(Image), matching: find.byType(Opacity))
            .first,
      );
      expect(later.opacity, 1.0);
      await tester.pumpAndSettle();
    });

    testWidgets('un toque la salta', (tester) async {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(SplashScreen));
      await tester.pumpAndSettle();
      expect(find.text('PANTALLA PRINCIPAL'), findsOneWidget);
    });

    testWidgets('con «reducir animaciones» dura mucho menos', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('PANTALLA PRINCIPAL'), findsOneWidget);
    });
  });

  testWidgets(
    'La aplicación arranca con la bienvenida y llega a la principal',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const ZaragozaCulturaApp());
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('Bienvenid@ a'), findsOneWidget);
      expect(find.textContaining('Maña Zaragoza'), findsOneWidget);
    },
  );
}
