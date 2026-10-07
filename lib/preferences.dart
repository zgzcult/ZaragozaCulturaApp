/// «Mis preferencias»: el usuario marca los tipos de actividad que más le
/// gustan, por orden de prioridad. Se usa para ordenar las recomendaciones y
/// los filtros de la agenda. Se guarda solo en el teléfono.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand.dart';
import 'day_suggestion.dart';
import 'event_classifier.dart';
import 'main.dart';

/// Categorías preferidas, de la más a la menos prioritaria.
class CategoryPreferences {
  const CategoryPreferences._();

  static const String _key = 'preferred_categories';

  static Future<List<CulturalCategory>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_key) ?? const <String>[];
      return [
        for (final name in names)
          for (final category in suggestionCategories)
            if (category.name == name) category,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<CulturalCategory> preferred) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final c in preferred) c.name]);
  }
}

/// Las categorías en el orden del usuario: primero las preferidas, por su
/// prioridad, y después el resto en su orden habitual.
List<CulturalCategory> categoriesByPreference(
  List<CulturalCategory> preferred, {
  List<CulturalCategory> all = suggestionCategories,
}) {
  return [
    for (final category in preferred)
      if (all.contains(category)) category,
    for (final category in all)
      if (!preferred.contains(category)) category,
  ];
}

/// Marca o desmarca una categoría. Al marcarla pasa a ser la última
/// prioridad; al desmarcarla, las siguientes suben un puesto.
List<CulturalCategory> togglePreference(
  List<CulturalCategory> preferred,
  CulturalCategory category,
) {
  return preferred.contains(category)
      ? [
          for (final c in preferred)
            if (c != category) c,
        ]
      : [...preferred, category];
}

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  List<CulturalCategory> _preferred = const [];

  @override
  void initState() {
    super.initState();
    CategoryPreferences.load().then((value) {
      if (mounted) setState(() => _preferred = value);
    });
  }

  void _toggle(CulturalCategory category) {
    setState(() => _preferred = togglePreference(_preferred, category));
    CategoryPreferences.save(_preferred);
  }

  void _clear() {
    setState(() => _preferred = const []);
    CategoryPreferences.save(_preferred);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.cream,
      appBar: AppBar(title: const Text('Mis preferencias')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            const Text(
              'Selecciona tus intereses favoritos para darles prioridad en '
              'las recomendaciones.',
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: Color(0xFF425B71),
              ),
            ),
            const SizedBox(height: 18),
            for (final category in suggestionCategories)
              _CategoryTile(
                category: category,
                // 0 = sin marcar; 1 = máxima prioridad.
                priority: _preferred.indexOf(category) + 1,
                onTap: () => _toggle(category),
              ),
            if (_preferred.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clear,
                  style: TextButton.styleFrom(foregroundColor: Brand.coralDeep),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Borrar mi selección'),
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'Tus preferencias se guardarán exclusivamente en tu dispositivo.',
              style: TextStyle(fontSize: 12, color: Brand.slate),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final CulturalCategory category;
  final int priority;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.priority,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = priority > 0;
    final label = categoryLabel(category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        label: selected ? '$label, prioridad $priority' : '$label, sin marcar',
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? Brand.navy : Brand.line,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(categoryIcon(category), color: Brand.navy),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: Brand.navy,
                      ),
                    ),
                  ),
                  // Número de prioridad, o un círculo vacío si no está
                  // marcada.
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? Brand.navy : Colors.transparent,
                      border: Border.all(
                        color: selected ? Brand.navy : const Color(0xFF8A97A8),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Text(
                            '$priority',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
