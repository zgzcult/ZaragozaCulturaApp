# Backend de extracción de eventos culturales

Este directorio contiene la base del pipeline de extracción de datos para la app de agenda cultural de Zaragoza.

## Qué incluye

- `scraper/scraper.py`: extractor del calendario y de las fichas del Ayuntamiento de Zaragoza
- Generación de JSON final para consumo desde Flutter
- Normalización de eventos y categorías

## Objetivo

La app móvil no debe depender directamente de la estructura HTML de la web pública. En cambio, el backend:

1. consulta el dataset oficial que utiliza el calendario de Zaragoza Cultura
2. expande cada subevento por día y horario de apertura
3. normaliza campos y conserva el enlace de la ficha oficial
4. genera un JSON limpio
5. permite que Flutter solo consuma ese JSON

## Ejecutar el scraper

Desde la raíz del proyecto:

```bash
python backend/scraper/scraper.py --base-url https://www.zaragoza.es/sede/servicio/cultura/ --output backend/data/zaragoza_events.json --limit 10000
```

## Resultado esperado

Se genera un archivo JSON con eventos normalizados, por ejemplo:

```json
[
  {
    "id": "...",
    "title": "Exposición de arte",
    "description": "...",
    "category": "exposiciones",
    "date": "2026-09-17",
    "time": "08:00",
    "place": "Centro Cívico Distrito 14 (La Jota)",
    "officialUrl": "https://www.zaragoza.es/sede/servicio/cultura/evento/314039",
    "source": "ayuntamiento",
    "lastUpdated": "2026-09-17T10:00:00Z"
  }
]
```

## Recomendación de integración

Cuando el backend esté funcionando, la app Flutter deberá consumir ese JSON en vez de hacer scraping directo.

La siguiente mejora recomendada es añadir un endpoint http o un JSON estático servido desde un backend propio.
