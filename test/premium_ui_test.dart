import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/ui_kit.dart';

CulturalEvent _event() => CulturalEvent(
  id: 'e1',
  title: 'Concierto de prueba',
  description: 'Descripción de la actividad.',
  category: CulturalCategory.musica,
  date: '2026-10-10',
  time: '20:00',
  place: 'Auditorio',
  officialUrl: 'https://www.zaragoza.es',
  timeSlots: const ['20:00'],
);

/// Lista con una tarjeta que abre la ficha, como en la agenda.
class _CardHost extends StatefulWidget {
  const _CardHost();

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  bool favorite = false;

  @override
  Widget build(BuildContext context) {
    final event = _event();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EventCard(
            event: event,
            isFavorite: favorite,
            onFavorite: () => setState(() => favorite = !favorite),
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventDetailScreen(
                  event: event,
                  isFavorite: favorite,
                  onToggleFavorite: () => setState(() => favorite = !favorite),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('la tarjeta muestra fecha, categoría y título sobre la foto', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _CardHost()));
    expect(find.text('10'), findsOneWidget);
    expect(find.text('OCT'), findsOneWidget);
    expect(find.text('Música'), findsOneWidget);
    expect(find.text('Concierto de prueba'), findsOneWidget);
    expect(find.byType(Hero), findsOneWidget);
  });

  testWidgets('el corazón late y vibra al guardar un favorito', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    await tester.pumpWidget(const MaterialApp(home: _CardHost()));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byType(FavoriteHeart));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    // A mitad de la animación el corazón está más grande de lo normal.
    await tester.pump(const Duration(milliseconds: 150));
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(
        of: find.byIcon(Icons.favorite),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, greaterThan(1.0));
    await tester.pumpAndSettle();
    expect(scale.scale.value, 1.0);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('la ficha tiene la foto plegable y los botones fijos abajo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(const MaterialApp(home: _CardHost()));
    await tester.tap(find.text('Concierto de prueba'));
    await tester.pumpAndSettle();

    expect(find.byType(SliverAppBar), findsOneWidget);
    // La imagen viaja de la tarjeta a la ficha.
    expect(find.byType(Hero), findsOneWidget);
    for (final label in ['Compartir', 'Calendario', 'Favorito']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // Al guardar, el botón cambia y el estado llega a la lista.
    await tester.tap(find.text('Favorito'));
    await tester.pumpAndSettle();
    expect(find.text('Guardado'), findsOneWidget);

    // Al bajar, la foto se pliega y el título pasa a la barra.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Compartir'), findsOneWidget);
    expect(find.text('Concierto de prueba'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mientras carga se ven esqueletos en vez de un círculo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkeletonList())),
    );
    expect(find.byType(SkeletonCard), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
  });
}
