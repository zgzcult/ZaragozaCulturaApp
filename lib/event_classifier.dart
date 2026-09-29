/// Categorías de la agenda y clasificación de actividades.
///
/// Los datos del ayuntamiento traen una categoría poco fiable (por ejemplo,
/// muchas exposiciones llegan como "teatro"), así que se reclasifica a partir
/// del título, el lugar y el comienzo de la descripción.
library;

enum CulturalCategory {
  all,
  musica,
  teatro,
  exposiciones,
  gastronomia,
  cine,
  charlas,
  eventos,
}

String _normalize(String value) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}

bool _has(String text, RegExp pattern) => pattern.hasMatch(text);

final RegExp _exposicion = RegExp(
  r'\bexposicion(es)?\b|\bmuestra (de|fotograf)|\binstalacion\b|'
  r'\bfotografi|\bretrospectiva\b|\bvisita guiada\b|\bitinerario\b|'
  r'\bcartel(es)? de\b',
);
final RegExp _exposicionLugar = RegExp(
  r'\bmuseo\b|sala de exposiciones|\biaacc\b|\bgaleria\b|'
  r'centro de historias|palacio de montemuzo|\bpalacio de sastago\b|'
  r'\bla lonja\b|torreon de la zuda|\bcentro de arte\b',
);
final RegExp _cine = RegExp(
  r'\bcine\b|\bpelicula|\bproyeccion|\bfilmoteca\b|\bdocumental|'
  r'\bcortometraje|\bfestival de cine\b|\bcineforum\b',
);
final RegExp _gastronomia = RegExp(
  r'gastronom|\btapas?\b|\bdegustacion|\bcata\b|\bcatas\b|\bvinos?\b|'
  r'food ?truck|\bcocina\b|\bcocinero|\bpintxo|\bruta de tapas\b|'
  r'\bjamon\b|\bcerveza|\bmercado gastron|\bbrunch\b|\bchocolate\b',
);
final RegExp _musica = RegExp(
  r'\bconcierto|\bmusica\b|\bmusical\b|\bjazz\b|\bblues\b|\brock\b|'
  r'\bflamenco\b|\bdj\b|\bdjs\b|\bcoro\b|\borquesta\b|\bbanda\b|'
  r'\brecital\b|\bcantautor|\bopera\b|\bzarzuela\b|\bfestival\b|'
  r'\bsesion (de )?dj\b|\bjota\b|\bjotas\b|\btardeo\b|\bdirecto\b',
);
final RegExp _teatro = RegExp(
  r'\bteatro\b|\bobra\b|\bcomedia\b|\bmonologo|\bdanza\b|\bcircuito\b|'
  r'\bcirco\b|\bmagia\b|\bmago\b|\bhumor\b|\bcabaret\b|\bimpro\b|'
  r'\bclown\b|\bperformance\b|\bespectaculo\b|\bballet\b|\bbaile\b|'
  r'\bbarraca\b|\bcomedy\b|\bcuentacuentos\b|\bbebecuentos\b|\bcuentos?\b|'
  r'\btiteres\b|\binfantil|\bpeques\b',
);
final RegExp _charlas = RegExp(
  r'\bconferencia|\bcharla|\bcoloquio|\bpresentacion (del? |de la )?(libro|novela|poemario)|\bpoemario\b|\bpresentacion libro\b|'
  r'\bclub de lectura\b|\btaller(es)?\b|\bcurso\b|\bjornadas?\b|'
  r'\bmesa redonda\b|\bponencia|\bdebate\b|\bencuentro con\b|\bclases? de\b',
);

int? _minutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

/// Devuelve la categoría más adecuada para una actividad.
///
/// Orden de prioridad: título, lugar, categoría de origen y, solo si sigue
/// sin haber pista clara, el comienzo de la descripción.
CulturalCategory classifyEvent({
  required String title,
  String place = '',
  String description = '',
  String sourceCategory = '',
  String time = '',
  String endTime = '',
}) {
  final t = _normalize(title);
  final p = _normalize(place);

  // 1. El título manda: es lo más específico.
  if (_has(t, _exposicion)) return CulturalCategory.exposiciones;
  if (_has(t, _cine)) return CulturalCategory.cine;
  if (_has(t, _gastronomia)) return CulturalCategory.gastronomia;
  if (_has(t, _charlas)) return CulturalCategory.charlas;
  if (_has(t, _musica)) return CulturalCategory.musica;
  if (_has(t, _teatro)) return CulturalCategory.teatro;

  // 2. El lugar orienta cuando el título no dice nada.
  if (p.contains('teatro')) return CulturalCategory.teatro;
  if (_has(p, _exposicionLugar)) return CulturalCategory.exposiciones;
  if (p.contains('biblioteca') || p.contains('centro de convivencia')) {
    return CulturalCategory.charlas;
  }
  if (p.contains('sala de musica')) return CulturalCategory.musica;
  if (p.contains('libreria')) return CulturalCategory.charlas;

  // 3. Categoría de origen. Un "teatro" con horario largo (p. ej. 17:00 a
  //    21:00) es en realidad una exposición con horario de apertura.
  final source = culturalCategoryFromString(sourceCategory);
  if (source == CulturalCategory.teatro) {
    final start = _minutes(time);
    final end = _minutes(endTime);
    if (start != null && end != null && end - start >= 180) {
      return CulturalCategory.exposiciones;
    }
  }
  // Las categorías de origen "cine", "infantil" y "conferencias" resultaron
  // poco fiables (llegan en actos que no lo son), así que no se aceptan.
  const trusted = {
    CulturalCategory.musica,
    CulturalCategory.teatro,
    CulturalCategory.exposiciones,
    CulturalCategory.gastronomia,
  };
  if (trusted.contains(source)) return source;

  // 4. Sin pistas: se mira el comienzo de la descripción.
  final d = _normalize(
    description.length > 200 ? description.substring(0, 200) : description,
  );
  if (_has(d, _exposicion)) return CulturalCategory.exposiciones;
  if (_has(d, _gastronomia)) return CulturalCategory.gastronomia;
  if (_has(d, _musica)) return CulturalCategory.musica;
  if (_has(d, _teatro)) return CulturalCategory.teatro;
  return CulturalCategory.eventos;
}

CulturalCategory culturalCategoryFromString(String? value) {
  switch (_normalize((value ?? '').trim())) {
    case 'musica':
      return CulturalCategory.musica;
    case 'teatro':
      return CulturalCategory.teatro;
    case 'gastronomia':
      return CulturalCategory.gastronomia;
    case 'exposiciones':
      return CulturalCategory.exposiciones;
    case 'cine':
      return CulturalCategory.cine;
    case 'conferencias':
    case 'charlas':
      return CulturalCategory.charlas;
    default:
      return CulturalCategory.eventos;
  }
}
