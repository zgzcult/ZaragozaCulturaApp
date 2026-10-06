import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zaragoza_cultura_app/brand.dart';
import 'package:zaragoza_cultura_app/crash_reporter.dart';
import 'package:zaragoza_cultura_app/event_classifier.dart';
import 'package:zaragoza_cultura_app/event_submission.dart';
import 'package:zaragoza_cultura_app/main.dart';
import 'package:zaragoza_cultura_app/suggestion.dart';

class _FakeClient extends SubmissionClient {
  final SubmitResult result;
  final List<Map<String, String>> sent = [];

  _FakeClient(this.result);

  @override
  Future<SubmitResult> send({
    required String type,
    required String title,
    required String description,
    String contact = '',
  }) async {
    sent.add({
      'type': type,
      'title': title,
      'description': description,
      'contact': contact,
    });
    return result;
  }
}

CulturalEvent _event({bool free = false, String id = 'e1'}) => CulturalEvent(
  id: id,
  title: free ? 'Concierto gratis' : 'Concierto de pago',
  description: '',
  category: CulturalCategory.musica,
  date: _today(),
  time: '',
  place: 'Sala',
  officialUrl: 'https://www.zaragoza.es',
  free: free,
);

String _today() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

class _Repo extends ZaragozaEventsRepository {
  const _Repo();

  @override
  Future<List<CulturalEvent>> loadCached() async => [
    _event(free: true, id: 'g'),
    _event(id: 'p'),
  ];

  @override
  Future<List<CulturalEvent>?> fetchFresh() async => loadCached();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Envía tu evento', () {
    test('el correo lleva los datos, sin líneas vacías', () {
      final text = buildEventDescription(
        date: DateTime(2026, 11, 12),
        time: ' 19:30 ',
        place: 'Sala Oasis, Calle Boggiero 28',
        organizer: 'Asociación X',
        description: '  Concierto solidario.  ',
      );
      expect(
        text,
        'Fecha: 12 de noviembre de 2026\n'
        'Hora: 19:30\n'
        'Lugar: Sala Oasis, Calle Boggiero 28\n'
        'Organiza: Asociación X\n'
        '\n'
        'Concierto solidario.',
      );
    });

    testWidgets('no envía si faltan datos obligatorios', (tester) async {
      final client = _FakeClient(SubmitResult.ok);
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      await tester.pumpWidget(
        MaterialApp(home: EventSubmissionScreen(client: client)),
      );
      await tester.tap(find.text('Enviar evento'));
      await tester.pumpAndSettle();
      expect(client.sent, isEmpty);
      expect(find.text('Escribe el nombre del evento.'), findsOneWidget);
      expect(find.text('Elige la fecha del evento.'), findsOneWidget);
      expect(find.text('Indica dónde se celebra.'), findsOneWidget);
      expect(
        find.text('Necesitamos un contacto para confirmar el evento.'),
        findsOneWidget,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('envía el evento por nuestro servidor, sin Google', (
      tester,
    ) async {
      final client = _FakeClient(SubmitResult.ok);
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventSubmissionScreen(
                      client: client,
                      clock: () => DateTime(2026, 10, 7),
                    ),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      Finder field(String label) => find.widgetWithText(TextFormField, label);
      await tester.enterText(field('Nombre del evento'), 'Concierto solidario');
      await tester.tap(field('Fecha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar')); // el día propuesto: hoy
      await tester.pumpAndSettle();
      await tester.enterText(field('Hora (opcional)'), '19:30');
      await tester.enterText(field('Lugar'), 'Sala Oasis');
      await tester.enterText(field('Descripción'), 'Música en directo.');
      await tester.enterText(
        field('Tu nombre o el de la organización'),
        'Asociación X',
      );
      await tester.enterText(
        field('Correo o teléfono de contacto'),
        'hola@example.org',
      );
      await tester.tap(find.text('Enviar evento'));
      await tester.pumpAndSettle();

      expect(client.sent, hasLength(1));
      final sent = client.sent.single;
      expect(sent['type'], 'evento');
      expect(sent['title'], 'Concierto solidario');
      expect(sent['contact'], 'hola@example.org');
      expect(sent['description'], contains('Fecha: 7 de octubre de 2026'));
      expect(sent['description'], contains('Hora: 19:30'));
      expect(sent['description'], contains('Lugar: Sala Oasis'));
      expect(sent['description'], contains('Música en directo.'));
      // Vuelve atrás y da las gracias.
      expect(find.text('abrir'), findsOneWidget);
      expect(find.textContaining('Hemos recibido tu evento'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    test('la app ya no enlaza ningún formulario de Google', () {
      for (final file in Directory('lib').listSync().whereType<File>()) {
        expect(
          file.readAsStringSync(),
          isNot(contains('docs.google.com')),
          reason: file.path,
        );
      }
    });
  });

  group('Entrada gratuita', () {
    test('se lee del dato y por defecto no es gratis', () {
      final base = {'id': '1', 'title': 'x', 'date': '2026-10-10'};
      expect(CulturalEvent.fromJson(base).free, isFalse);
      expect(CulturalEvent.fromJson({...base, 'free': true}).free, isTrue);
      expect(CulturalEvent.fromJson({...base, 'free': 'sí'}).free, isFalse);
      expect(
        CulturalEvent.fromJson({...base, 'free': true})
            .withTimeSlots(const ['10:00'])
            .free,
        isTrue,
      );
    });

    testWidgets('la agenda no filtra por gratis: el dato no es completo', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      await tester.pumpWidget(
        const MaterialApp(home: AgendaScreen(repository: _Repo())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gratis'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Concierto gratis'), findsOneWidget);
      expect(find.text('Concierto de pago'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('la ficha indica la entrada gratuita', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            event: _event(free: true),
            isFavorite: false,
            onToggleFavorite: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Entrada gratuita'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('Informes de errores', () {
    CrashReporter reporter(List<Map<String, String>> sent, {int max = 3}) =>
        CrashReporter(
          sender: (report) async => sent.add(report),
          maxPerSession: max,
          platform: 'android',
          osVersion: '14',
        );

    test('envía solo datos técnicos', () async {
      final sent = <Map<String, String>>[];
      expect(
        await reporter(sent).report(StateError('fallo'), StackTrace.current),
        isTrue,
      );
      expect(sent.single.keys.toSet(), {
        'error',
        'stack',
        'appVersion',
        'platform',
        'osVersion',
      });
      expect(sent.single['error'], contains('fallo'));
      expect(sent.single['appVersion'], Brand.appVersion);
    });

    test('la versión coincide con la de pubspec.yaml', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('version: ${Brand.appVersion}'),
      );
    });

    test('el mismo fallo solo se informa una vez y hay un tope', () async {
      final sent = <Map<String, String>>[];
      final r = reporter(sent, max: 2);
      final stack = StackTrace.current;
      await r.report(StateError('a'), stack);
      await r.report(StateError('a'), stack); // repetido
      await r.report(StateError('b'), stack);
      await r.report(StateError('c'), stack); // supera el tope
      expect(
        [for (final s in sent) s['error']],
        ['Bad state: a', 'Bad state: b'],
      );
    });

    test('si el usuario los desactiva no se envía nada', () async {
      await CrashReporter.setEnabled(false);
      final sent = <Map<String, String>>[];
      expect(await reporter(sent).report(StateError('x'), null), isFalse);
      expect(sent, isEmpty);
      expect(await CrashReporter.isEnabled(), isFalse);
    });

    test('un fallo al enviar no provoca otro error', () async {
      final r = CrashReporter(
        sender: (_) async => throw Exception('sin conexión'),
        platform: 'android',
        osVersion: '14',
      );
      expect(await r.report(StateError('x'), null), isFalse);
    });

    testWidgets('Ajustes permite desactivarlos', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            remindersEnabled: false,
            onRemindersChanged: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(
        SwitchListTile,
        'Enviar informes de errores',
      );
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(await CrashReporter.isEnabled(), isFalse);
      // «Envía tu evento» abre el formulario de la app.
      await tester.tap(find.text('Envía tu evento'));
      await tester.pumpAndSettle();
      expect(find.byType(EventSubmissionScreen), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
