import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';

class _FakeRepository extends ZaragozaEventsRepository {
  final List<CulturalEvent> events;

  const _FakeRepository(this.events);

  @override
  Future<List<CulturalEvent>> loadCached() async => events;

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => events;
}

CulturalEvent _event(String id, String title, int daysFromNow, String time) {
  final date = DateTime.now().add(Duration(days: daysFromNow));
  final key =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return CulturalEvent(
    id: id,
    title: title,
    description: 'Descripción',
    category: CulturalCategory.musica,
    date: key,
    time: time,
    place: 'Lugar de prueba',
    officialUrl: 'https://www.zaragoza.es',
    timeSlots: [time],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Favoritos: todos en una página, agrupados por día y en orden', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      // Guardados sin orden a propósito.
      'favorite_event_ids': ['lejano', 'hoy', 'proximo'],
    });
    final repo = _FakeRepository([
      _event('lejano', 'Concierto lejano', 10, '21:00'),
      _event('hoy', 'Concierto de hoy', 0, '20:00'),
      _event('proximo', 'Concierto de mañana', 1, '19:00'),
      _event('otro', 'No es favorito', 1, '10:00'),
    ]);

    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(ZaragozaCulturaApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();

    expect(find.text('No es favorito'), findsNothing);
    final hoy = tester.getTopLeft(find.text('Concierto de hoy')).dy;
    final manana = tester.getTopLeft(find.text('Concierto de mañana')).dy;
    final lejano = tester.getTopLeft(find.text('Concierto lejano')).dy;
    expect(hoy, lessThan(manana));
    expect(manana, lessThan(lejano));
    expect(find.textContaining('Hoy ·'), findsOneWidget);
    expect(find.textContaining('Mañana ·'), findsOneWidget);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Favoritos vacío muestra el mensaje de ayuda', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ZaragozaCulturaApp(repository: _FakeRepository([])),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no tienes favoritos'), findsOneWidget);
  });
}
