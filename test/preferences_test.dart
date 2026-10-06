import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/brand.dart';
import 'package:zaragoza_cultura_app/day_suggestion.dart';
import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/preferences.dart';

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

CulturalEvent _event(String title, CulturalCategory category) => CulturalEvent(
  id: title,
  title: title,
  description: '',
  category: category,
  date: _today(),
  time: '',
  place: 'Sala',
  officialUrl: 'https://www.zaragoza.es',
);

class _Repo extends ZaragozaEventsRepository {
  const _Repo();

  @override
  Future<List<CulturalEvent>> loadCached() async => [
    _event('Concierto', CulturalCategory.musica),
    _event('Obra', CulturalCategory.teatro),
    _event('Película', CulturalCategory.cine),
  ];

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => loadCached();
}

/// Número de prioridad que muestra la fila de una categoría («» si ninguno).
String _number(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final numbers = find.descendant(
    of: row.first,
    matching: find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d$').hasMatch(w.data ?? ''),
    ),
  );
  return numbers.evaluate().isEmpty
      ? ''
      : tester.widget<Text>(numbers.first).data!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Orden de prioridad', () {
    test('marcar añade al final y desmarcar sube a las siguientes', () {
      var list = <CulturalCategory>[];
      list = togglePreference(list, CulturalCategory.cine);
      list = togglePreference(list, CulturalCategory.musica);
      list = togglePreference(list, CulturalCategory.teatro);
      expect(list, [
        CulturalCategory.cine,
        CulturalCategory.musica,
        CulturalCategory.teatro,
      ]);
      list = togglePreference(list, CulturalCategory.cine);
      expect(list, [CulturalCategory.musica, CulturalCategory.teatro]);
    });

    test('primero las preferidas y luego el resto en su orden', () {
      final ordered = categoriesByPreference([
        CulturalCategory.cine,
        CulturalCategory.teatro,
      ]);
      expect(ordered.take(2), [CulturalCategory.cine, CulturalCategory.teatro]);
      expect(ordered, hasLength(suggestionCategories.length));
      expect(ordered.toSet(), suggestionCategories.toSet());
      expect(categoriesByPreference(const []), suggestionCategories);
    });

    test(
      'se guardan en el teléfono y se ignoran valores desconocidos',
      () async {
        await CategoryPreferences.save([
          CulturalCategory.teatro,
          CulturalCategory.musica,
        ]);
        expect(await CategoryPreferences.load(), [
          CulturalCategory.teatro,
          CulturalCategory.musica,
        ]);
        SharedPreferences.setMockInitialValues({
          'preferred_categories': ['cine', 'inventada', 'all'],
        });
        expect(await CategoryPreferences.load(), [CulturalCategory.cine]);
      },
    );

    test('las recomendaciones salen por orden de preferencia', () {
      final events = [
        _event('Concierto', CulturalCategory.musica),
        _event('Obra', CulturalCategory.teatro),
        _event('Película', CulturalCategory.cine),
      ];
      final now = DateTime.now();
      expect(
        [for (final s in pickDaySuggestions(events, now: now)) s.event.title],
        ['Concierto', 'Obra', 'Película'],
      );
      expect(
        [
          for (final s in pickDaySuggestions(
            events,
            now: now,
            preferred: const [CulturalCategory.cine, CulturalCategory.teatro],
          ))
            s.event.title,
        ],
        ['Película', 'Obra', 'Concierto'],
      );
    });
  });

  group('Pantalla', () {
    testWidgets('cada categoría marcada muestra su número de prioridad', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      await tester.pumpWidget(const MaterialApp(home: PreferencesScreen()));
      await tester.pumpAndSettle();
      expect(_number(tester, 'Cine'), '');
      expect(find.text('Borrar mi selección'), findsNothing);

      await tester.tap(find.text('Cine'));
      await tester.tap(find.text('Música'));
      await tester.tap(find.text('Teatro'));
      await tester.pumpAndSettle();
      expect(_number(tester, 'Cine'), '1');
      expect(_number(tester, 'Música'), '2');
      expect(_number(tester, 'Teatro'), '3');
      expect(await CategoryPreferences.load(), [
        CulturalCategory.cine,
        CulturalCategory.musica,
        CulturalCategory.teatro,
      ]);

      // Al quitar la primera, las demás suben.
      await tester.tap(find.text('Cine'));
      await tester.pumpAndSettle();
      expect(_number(tester, 'Cine'), '');
      expect(_number(tester, 'Música'), '1');
      expect(_number(tester, 'Teatro'), '2');

      await tester.tap(find.text('Borrar mi selección'));
      await tester.pumpAndSettle();
      expect(_number(tester, 'Música'), '');
      expect(await CategoryPreferences.load(), isEmpty);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('se abre desde Ajustes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2200));
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            remindersEnabled: false,
            onRemindersChanged: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mis preferencias'));
      await tester.pumpAndSettle();
      expect(find.byType(PreferencesScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('los filtros de la agenda siguen el orden elegido', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'preferred_categories': ['cine', 'teatro'],
      });
      await tester.binding.setSurfaceSize(const Size(1400, 1800));
      await tester.pumpWidget(
        const MaterialApp(home: AgendaScreen(repository: _Repo())),
      );
      await tester.pumpAndSettle();
      double x(String label) =>
          tester.getTopLeft(find.widgetWithText(ChoiceChip, label)).dx;
      expect(x('Todos'), lessThan(x('Cine')));
      expect(x('Cine'), lessThan(x('Teatro')));
      expect(x('Teatro'), lessThan(x('Música')));
      await tester.binding.setSurfaceSize(null);
    });
  });

  test('los tonos oscuros de la marca se leen sobre crema y blanco', () {
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) =>
        0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    double ratio(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      return (la > lb ? la + 0.05 : lb + 0.05) /
          (la > lb ? lb + 0.05 : la + 0.05);
    }

    for (final color in [
      Brand.coralDeep,
      Brand.skyDeep,
      Brand.green,
      Brand.slate,
      Brand.navy,
    ]) {
      expect(ratio(color, Brand.cream), greaterThanOrEqualTo(4.5));
      expect(ratio(color, Colors.white), greaterThanOrEqualTo(4.5));
    }
    // Los originales no lo alcanzan: por eso no se usan como texto.
    expect(ratio(Brand.coral, Brand.cream), lessThan(4.5));
    expect(ratio(Brand.sky, Colors.white), lessThan(4.5));
    // Sobre coral, el texto va en azul marino.
    expect(ratio(Brand.navy, Brand.coral), greaterThanOrEqualTo(4.5));
  });
}
