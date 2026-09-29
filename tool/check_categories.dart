// Uso: dart run tool/check_categories.dart build/ev.json
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zaragoza_cultura_app/event_classifier.dart';

void main(List<String> args) {
  final data = jsonDecode(File(args.first).readAsStringSync()) as List;
  final counts = <String, int>{};
  final samples = <String, List<String>>{};
  var changed = 0;
  for (final raw in data) {
    final e = Map<String, dynamic>.from(raw as Map);
    final cat = classifyEvent(
      title: '${e['title']}',
      place: '${e['place']}',
      description: '${e['description']}',
      sourceCategory: '${e['category']}',
      time: '${e['time']}',
      endTime: '${e['endTime']}',
    );
    if (cat != culturalCategoryFromString('${e['category']}')) changed++;
    counts[cat.name] = (counts[cat.name] ?? 0) + 1;
    samples.putIfAbsent(cat.name, () => []).add('${e['title']}  @ ${e['place']}');
  }
  print('total ${data.length}, reclasificadas $changed');
  final rnd = Random(4);
  for (final k in counts.keys) {
    print('\n== $k (${counts[k]})');
    final s = samples[k]!.toSet().toList()..shuffle(rnd);
    for (final line in s.take(8)) {
      print('  ${line.length > 100 ? line.substring(0, 100) : line}');
    }
  }
}
