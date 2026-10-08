import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/main.dart';

Map<String, dynamic> _json({bool? hideLink}) => {
  'id': 'e1',
  'title': 'Concierto en la plaza',
  'description': 'Texto propio.',
  'category': 'musica',
  'date': '2026-11-20',
  'time': '20:00',
  'place': 'Plaza del Pilar',
  'officialUrl': 'https://www.zaragoza.es/sede/servicio/cultura/evento/1',
  'moreInfoUrl': hideLink == true ? '' : 'https://teatro.example.org/acto',
  'hideLink': ?hideLink,
};

Widget _detail(CulturalEvent event) => MaterialApp(
  home: EventDetailScreen(
    event: event,
    isFavorite: false,
    onToggleFavorite: () {},
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el servidor marca las actividades sin enlace', () {
    expect(CulturalEvent.fromJson(_json(hideLink: true)).hideLink, isTrue);
    expect(CulturalEvent.fromJson(_json(hideLink: false)).hideLink, isFalse);
    expect(CulturalEvent.fromJson(_json()).hideLink, isFalse);
  });

  testWidgets('sin enlace no se enseña «Más información»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(
      _detail(CulturalEvent.fromJson(_json(hideLink: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Concierto en la plaza'), findsWidgets);
    expect(find.text('Más información'), findsNothing);

    await tester.pumpWidget(_detail(CulturalEvent.fromJson(_json())));
    await tester.pumpAndSettle();
    expect(find.text('Más información'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
