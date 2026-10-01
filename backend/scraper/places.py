#!/usr/bin/env python3
"""Lugares de interés (restaurantes...) desde los datos abiertos del Ayuntamiento.

Descarga el listado de restaurantes de zaragoza.es/sede/servicio/restaurante,
convierte sus coordenadas (UTM) a latitud/longitud y los guarda en MongoDB
(colección `places`) para que el servidor los entregue a la app.

Origen de los datos: Ayuntamiento de Zaragoza.

Uso:
    python backend/scraper/places.py              # descarga y guarda
    python backend/scraper/places.py --dry-run    # solo muestra un resumen
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

BASE = "https://www.zaragoza.es/sede/servicio"
PAGE_SIZE = 500  # máximo que devuelve la API por petición
HEADERS = {"User-Agent": "ZaragozaCulturaApp/1.0", "Accept": "application/json"}

KINDS = {
    "restaurante": {"endpoint": "restaurante", "prefix": "restaurante"},
}


def utm_to_latlng(easting: float, northing: float, zone: int = 30) -> Tuple[float, float]:
    """UTM (hemisferio norte, ETRS89/WGS84) -> (latitud, longitud) en grados."""
    a = 6378137.0
    f = 1 / 298.257222101
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    k0 = 0.9996

    x = easting - 500000.0
    m = northing / k0
    mu = m / (a * (1 - e2 / 4 - 3 * e2**2 / 64 - 5 * e2**3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    phi1 = (
        mu
        + (3 * e1 / 2 - 27 * e1**3 / 32) * math.sin(2 * mu)
        + (21 * e1**2 / 16 - 55 * e1**4 / 32) * math.sin(4 * mu)
        + (151 * e1**3 / 96) * math.sin(6 * mu)
        + (1097 * e1**4 / 512) * math.sin(8 * mu)
    )
    sin1, cos1, tan1 = math.sin(phi1), math.cos(phi1), math.tan(phi1)
    n1 = a / math.sqrt(1 - e2 * sin1**2)
    t1 = tan1**2
    c1 = ep2 * cos1**2
    r1 = a * (1 - e2) / (1 - e2 * sin1**2) ** 1.5
    d = x / (n1 * k0)

    lat = phi1 - (n1 * tan1 / r1) * (
        d**2 / 2
        - (5 + 3 * t1 + 10 * c1 - 4 * c1**2 - 9 * ep2) * d**4 / 24
        + (61 + 90 * t1 + 298 * c1 + 45 * t1**2 - 252 * ep2 - 3 * c1**2) * d**6 / 720
    )
    lon0 = math.radians(zone * 6 - 183)
    lon = lon0 + (
        d
        - (1 + 2 * t1 + c1) * d**3 / 6
        + (5 - 2 * c1 + 28 * t1 - 3 * c1**2 + 8 * ep2 + 24 * t1**2) * d**5 / 120
    ) / cos1
    return round(math.degrees(lat), 6), round(math.degrees(lon), 6)


_SMALL_WORDS = {"de", "del", "la", "las", "el", "los", "y", "e", "o", "en", "a", "al", "con", "por"}


def clean_name(raw: str) -> str:
    """«RESTAURANTE EL CACHIRULO» -> «El Cachirulo». Respeta los nombres que ya
    vienen en mayúsculas y minúsculas."""
    name = re.sub(r"\s+", " ", (raw or "").strip())
    name = re.sub(r"^(restaurante|rte\.?|bar restaurante)\s+", "", name, flags=re.I)
    if not name:
        return ""
    if name.isupper() or name.islower():
        words = name.lower().split(" ")
        out = []
        for i, word in enumerate(words):
            if i > 0 and word in _SMALL_WORDS:
                out.append(word)
            else:
                out.append(word[:1].upper() + word[1:])
        name = " ".join(out)
    return name


def _text(value: Any) -> str:
    return re.sub(r"\s+", " ", value).strip() if isinstance(value, str) else ""


def _coordinates(raw: Dict[str, Any]) -> Tuple[Optional[float], Optional[float]]:
    """(lat, lng) del lugar, o (None, None) si no tiene o son erróneas."""
    coords = (raw.get("geometry") or {}).get("coordinates")
    if not isinstance(coords, (list, tuple)) or len(coords) < 2:
        return None, None
    try:
        east, north = float(coords[0]), float(coords[1])
    except (TypeError, ValueError):
        return None, None
    if abs(east) <= 180 and abs(north) <= 90:  # ya vienen en grados (lon, lat)
        lat, lng = round(north, 6), round(east, 6)
    else:
        lat, lng = utm_to_latlng(east, north)
    # Dentro del entorno de Zaragoza; fuera de ahí, el dato es erróneo.
    if not (41.3 <= lat <= 42.0 and -1.4 <= lng <= -0.5):
        return None, None
    return lat, lng


def normalize_place(kind: str, raw: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Datos de un lugar, o None si no sirve (sin nombre, o sin coordenadas y
    sin dirección). Los lugares sin coordenadas se guardan con lat/lng nulos:
    la app los muestra en la lista y los localiza con Google Maps."""
    name = clean_name(_text(raw.get("title")))
    if not name:
        return None
    lat, lng = _coordinates(raw)

    street = _text(raw.get("streetAddress"))
    postal = _text(raw.get("postalCode"))
    address = ", ".join(p for p in (street, postal) if p)
    if lat is None and not street:
        return None
    tel = raw.get("tel")
    phone = _text(tel.get("tel")) if isinstance(tel, dict) else _text(tel)
    url = _text(raw.get("url"))
    if url and not re.match(r"https?://", url, re.I):
        url = ""
    return {
        "id": f"{KINDS[kind]['prefix']}-{raw.get('id')}",
        "type": kind,
        "name": name,
        "address": address,
        "phone": phone,
        "url": url,
        "lat": lat,
        "lng": lng,
        "source": "ayuntamiento",
        "lastUpdated": datetime.now(timezone.utc).isoformat(),
    }


def fetch_all(kind: str, fetch=None) -> List[Dict[str, Any]]:
    """Descarga todas las páginas del listado."""
    fetch = fetch or _fetch_page
    items: List[Dict[str, Any]] = []
    start = 0
    total = None
    while total is None or start < total:
        page = fetch(kind, start)
        total = int(page.get("totalCount", 0))
        result = page.get("result") or []
        if not result:
            break
        items.extend(result)
        start += PAGE_SIZE
        time.sleep(0.3)
    return items


def _fetch_page(kind: str, start: int) -> Dict[str, Any]:
    url = f"{BASE}/{KINDS[kind]['endpoint']}.json?rows={PAGE_SIZE}&start={start}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def collect(kind: str, fetch=None) -> List[Dict[str, Any]]:
    seen = set()
    places = []
    for raw in fetch_all(kind, fetch):
        place = normalize_place(kind, raw)
        if place and place["id"] not in seen:
            seen.add(place["id"])
            places.append(place)
    return places


def save(kind: str, places: List[Dict[str, Any]], collection) -> None:
    """Guarda los lugares y elimina los que ya no están en el listado oficial.
    Salvaguardas: no borra si se descargaron muy pocos ni si fuese a borrar más
    del 40 %."""
    for place in places:
        collection.update_one({"id": place["id"]}, {"$set": place}, upsert=True)
    print(f"[OK] {len(places)} lugares '{kind}' guardados.")

    if len(places) < 200:
        print("[INFO] Limpieza omitida: se descargaron pocos lugares.")
        return
    fresh = {p["id"] for p in places}
    existing = [d["id"] for d in collection.find({"type": kind}, {"id": 1, "_id": 0})]
    stale = [i for i in existing if i not in fresh]
    if not stale:
        return
    if len(stale) > 0.4 * max(1, len(existing)):
        print(f"[WARN] Limpieza cancelada: borraría {len(stale)} de {len(existing)}.")
        return
    collection.delete_many({"type": kind, "id": {"$in": stale}})
    print(f"[OK] Limpieza: {len(stale)} lugares obsoletos eliminados.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="solo muestra un resumen, sin guardar")
    args = parser.parse_args()

    uri = os.environ.get("MONGODB_URI")
    if not args.dry_run and not uri:
        print("[ERROR] MONGODB_URI no configurada", file=sys.stderr)
        return 1

    for kind in KINDS:
        places = collect(kind)
        with_coords = sum(1 for p in places if p["lat"] is not None)
        print(f"[INFO] {kind}: {len(places)} lugares válidos ({with_coords} con coordenadas, {len(places) - with_coords} solo en lista)")
        if args.dry_run:
            for place in places[:3]:
                print("  ", place["name"], "|", place["address"], "|", place["lat"], place["lng"])
            continue
        if len(places) < 200:
            print(f"[ERROR] Demasiado pocos lugares '{kind}'; no se guarda nada.", file=sys.stderr)
            return 1
        from pymongo import MongoClient

        client = MongoClient(uri, serverSelectionTimeoutMS=10000)
        save(kind, places, client["zaragoza_cultura"]["places"])
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
