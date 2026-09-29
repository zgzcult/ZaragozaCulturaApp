#!/usr/bin/env python3
"""Busca imágenes coherentes para las actividades que no tienen una propia.

Problema: la web del ayuntamiento a veces no trae imagen, o reutiliza la misma
(p. ej. el cartel de las fiestas) en decenas de actos sin relación entre sí.

Solución, para cada título de actividad afectado:
1. Groq (LLM) propone una búsqueda corta en inglés para una foto genérica.
2. Pexels (banco de imágenes gratuito) devuelve una foto para esa búsqueda.
3. Se guarda en MongoDB como `fallbackImageUrl` + `imageCredit` (Pexels pide
   citar al fotógrafo). Las imágenes compartidas se marcan `genericImage`.

Variables de entorno:
    MONGODB_URI      conexión a MongoDB Atlas
    GROQ_API_KEY     clave de Groq (https://console.groq.com)
    PEXELS_API_KEY   clave de Pexels (https://www.pexels.com/api/)

Uso:
    python backend/scraper/enrich_images.py --dry-run     # no usa la red
    python backend/scraper/enrich_images.py --max-queries 200
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date, timedelta
from typing import Any, Dict, List, Optional

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODELS_URL = "https://api.groq.com/openai/v1/models"
# Modelos de texto por orden de preferencia; se usa el primero que la clave
# tenga disponible (GROQ_MODEL fuerza uno concreto).
GROQ_MODEL_PREFERENCE = [
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "openai/gpt-oss-20b",
    "openai/gpt-oss-120b",
]
PEXELS_URL = "https://api.pexels.com/v1/search"

# Una imagen usada por este número de títulos distintos (o más) se considera
# genérica: es un cartel/banner compartido, no una foto del acto.
GENERIC_MIN_TITLES = 3

SYSTEM_PROMPT = (
    "Eres un asistente que elige fotos de stock para una agenda cultural. "
    "Recibes datos de una actividad (en español) y respondes SOLO con un JSON "
    '{"query": "..."} donde query son 2 a 4 palabras en inglés que describen '
    "una foto genérica y realista adecuada para ilustrar la actividad "
    "(instrumentos, escenario, museo, comida, biblioteca, etc.). No incluyas "
    "nombres de personas, marcas, ciudades ni texto que deba aparecer en la foto."
)


def normalize_title(title: str) -> str:
    return re.sub(r"\s+", " ", title.strip().lower())


def absolute_url(value: str) -> str:
    if value.startswith("//"):
        return "https:" + value
    if value.startswith("/"):
        return "https://www.zaragoza.es" + value
    return value


def find_generic_images(events: List[Dict[str, Any]]) -> set:
    titles_by_image: Dict[str, set] = defaultdict(set)
    for event in events:
        image = event.get("imageUrl") or ""
        if image:
            titles_by_image[image].add(normalize_title(event.get("title", "")))
    return {img for img, titles in titles_by_image.items() if len(titles) >= GENERIC_MIN_TITLES}


def http_json(url: str, headers: Dict[str, str], body: Optional[dict] = None, retries: int = 3) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers)
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 429 and attempt < retries - 1:
                wait = int(exc.headers.get("Retry-After", "5") or 5)
                time.sleep(min(wait, 30))
                continue
            detail = exc.read().decode("utf-8", "replace")[:300]
            raise RuntimeError(f"HTTP {exc.code} en {url.split('?')[0]}: {detail}") from exc
    raise RuntimeError("sin respuesta")


def pick_groq_model(api_key: str) -> str:
    forced = os.environ.get("GROQ_MODEL")
    if forced:
        return forced
    result = http_json(
        GROQ_MODELS_URL,
        {"Authorization": f"Bearer {api_key}", "User-Agent": "zaragoza-cultura-app/1.0"},
    )
    available = {m.get("id") for m in result.get("data", [])}
    for model in GROQ_MODEL_PREFERENCE:
        if model in available:
            return model
    raise RuntimeError(f"Ningún modelo preferido disponible. Disponibles: {sorted(x for x in available if x)}")


def groq_query(api_key: str, model: str, event: Dict[str, Any]) -> Optional[str]:
    description = (event.get("description") or "")[:300]
    user = (
        f"Título: {event.get('title', '')}\n"
        f"Lugar: {event.get('place', '')}\n"
        f"Categoría: {event.get('category', '')}\n"
        f"Descripción: {description}"
    )
    result = http_json(
        GROQ_URL,
        {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "zaragoza-cultura-app/1.0",
        },
        {
            "model": model,
            "temperature": 0.2,
            # margen para modelos que "razonan" antes de responder
            "max_tokens": 400,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user},
            ],
        },
    )
    try:
        content = result["choices"][0]["message"]["content"] or ""
        match = re.search(r"\{.*?\}", content, re.S)
        query = str(json.loads(match.group(0)).get("query", "")).strip() if match else ""
    except (KeyError, IndexError, ValueError, AttributeError):
        return None
    query = re.sub(r"[^A-Za-z0-9 \-]", "", query)[:60].strip()
    return query or None


def pexels_photo(api_key: str, query: str) -> Optional[Dict[str, str]]:
    url = f"{PEXELS_URL}?{urllib.parse.urlencode({'query': query, 'per_page': 5, 'orientation': 'landscape'})}"
    result = http_json(url, {"Authorization": api_key, "User-Agent": "zaragoza-cultura-app/1.0"})
    photos = result.get("photos") or []
    if not photos:
        return None
    photo = photos[0]
    return {
        "url": photo["src"].get("large") or photo["src"]["original"],
        "photographer": photo.get("photographer", ""),
        "photographerUrl": photo.get("photographer_url", ""),
        "pexelsUrl": photo.get("url", ""),
    }


def load_events(collection) -> List[Dict[str, Any]]:
    """Actividades próximas (hoy en adelante, unos 4 meses)."""
    start = (date.today() - timedelta(days=1)).isoformat()
    end = (date.today() + timedelta(days=120)).isoformat()
    projection = {"_id": 0, "id": 1, "title": 1, "place": 1, "category": 1,
                  "description": 1, "imageUrl": 1, "fallbackImageUrl": 1, "genericImage": 1}
    return list(collection.find({"date": {"$gte": start, "$lte": end}}, projection))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="solo muestra qué haría, sin usar Groq/Pexels ni escribir")
    parser.add_argument("--max-queries", type=int, default=300, help="máximo de títulos a procesar por ejecución")
    parser.add_argument("--from-json", help="leer eventos de un JSON local (solo con --dry-run)")
    args = parser.parse_args()

    uri = os.environ.get("MONGODB_URI")
    groq_key = os.environ.get("GROQ_API_KEY")
    pexels_key = os.environ.get("PEXELS_API_KEY")

    collection = None
    if args.from_json:
        if not args.dry_run:
            print("[ERROR] --from-json solo se permite con --dry-run", file=sys.stderr)
            return 1
        with open(args.from_json, encoding="utf-8") as fh:
            events = json.load(fh)
    else:
        if not uri:
            print("[ERROR] MONGODB_URI no configurada", file=sys.stderr)
            return 1
        from pymongo import MongoClient

        client = MongoClient(uri, serverSelectionTimeoutMS=10000)
        collection = client["zaragoza_cultura"]["events"]
        events = load_events(collection)

    generic = find_generic_images(events)
    for event in events:
        event["_generic"] = (event.get("imageUrl") or "") in generic

    # Un candidato por título (los repetidos comparten imagen).
    by_title: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for event in events:
        by_title[normalize_title(event.get("title", ""))].append(event)

    pending = []
    for title, group in by_title.items():
        needs = any(not e.get("imageUrl") or e["_generic"] for e in group)
        done = any(e.get("fallbackImageUrl") for e in group)
        if needs and not done:
            pending.append((title, group))

    print(f"[INFO] {len(events)} actividades, {len(by_title)} títulos, "
          f"{len(generic)} imágenes genéricas, {len(pending)} títulos por resolver")

    if args.dry_run:
        for title, group in pending[:15]:
            print(f"  - {group[0].get('title', '')[:70]}")
        return 0

    if not groq_key or not pexels_key:
        print("[WARN] Faltan GROQ_API_KEY o PEXELS_API_KEY: solo se marcan las imágenes genéricas.")

    # Marcar imágenes genéricas aunque no haya claves.
    generic_ids = [e["id"] for e in events if e["_generic"] and not e.get("genericImage")]
    if generic_ids:
        collection.update_many({"id": {"$in": generic_ids}}, {"$set": {"genericImage": True}})

    if not groq_key or not pexels_key:
        return 0

    try:
        model = pick_groq_model(groq_key)
    except Exception as exc:
        print(f"[ERROR] No se pudo elegir modelo de Groq: {exc}", file=sys.stderr)
        return 0
    print(f"[INFO] Modelo de Groq: {model}")

    cache = collection.database["image_cache"]
    resolved = 0
    failures = 0
    for title, group in pending[: args.max_queries]:
        sample = group[0]
        try:
            query = groq_query(groq_key, model, sample)
            if not query:
                continue
            cached = cache.find_one({"_id": query})
            photo = cached["photo"] if cached else pexels_photo(pexels_key, query)
            if not cached:
                cache.replace_one({"_id": query}, {"_id": query, "photo": photo}, upsert=True)
                time.sleep(0.4)  # respeta los límites gratuitos
            if not photo:
                continue
            ids = [e["id"] for e in group]
            collection.update_many(
                {"id": {"$in": ids}},
                {"$set": {
                    "fallbackImageUrl": photo["url"],
                    "imageCredit": {"photographer": photo["photographer"], "url": photo["photographerUrl"]},
                }},
            )
            resolved += 1
            print(f"[OK] {sample.get('title', '')[:50]!r} -> {query!r}")
        except Exception as exc:  # una actividad no debe parar al resto
            failures += 1
            print(f"[WARN] {sample.get('title', '')[:50]!r}: {exc}", file=sys.stderr)
            if failures >= 5 and resolved == 0:
                print("[ERROR] Demasiados fallos seguidos; se detiene para no gastar cupo.", file=sys.stderr)
                break

    print(f"[OK] {resolved} títulos con imagen de reserva.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
