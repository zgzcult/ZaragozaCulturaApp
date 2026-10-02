#!/usr/bin/env python3
"""Lugares de interés (restaurantes, monumentos y museos) desde los datos
abiertos del Ayuntamiento.

Descarga los listados de zaragoza.es/sede/servicio/restaurante y /monumento,
convierte sus coordenadas (UTM ED50) a latitud/longitud y los guarda en MongoDB
(colección `places`) para que el servidor los entregue a la app.

Origen de los datos: Ayuntamiento de Zaragoza.

Uso:
    python backend/scraper/places.py              # descarga y guarda
    python backend/scraper/places.py --dry-run    # solo muestra un resumen
"""

from __future__ import annotations

import argparse
import html
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

BASE = "https://www.zaragoza.es/sede/servicio"
PAGE_SIZE = 500  # máximo que devuelve la API por petición
HEADERS = {"User-Agent": "ZaragozaCulturaApp/1.0", "Accept": "application/json"}

KINDS = {
    # min: si se descargan menos, algo ha fallado y no se guarda nada.
    "restaurante": {"endpoint": "restaurante", "prefix": "restaurante", "min": 200},
    "monumento": {"endpoint": "monumento", "prefix": "monumento", "min": 100},
}


# Elipsoides: Hayford/Internacional 1924 (ED50) y WGS84.
_HAYFORD = (6378388.0, 1 / 297.0)
_WGS84 = (6378137.0, 1 / 298.257223563)


def _utm_inverse(easting: float, northing: float, a: float, f: float, zone: int) -> Tuple[float, float]:
    """UTM -> (latitud, longitud) en radianes, sobre el elipsoide dado."""
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
    return lat, lon


def _to_ecef(lat: float, lon: float, a: float, f: float) -> Tuple[float, float, float]:
    e2 = f * (2 - f)
    n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
    return (n * math.cos(lat) * math.cos(lon), n * math.cos(lat) * math.sin(lon), n * (1 - e2) * math.sin(lat))


def _from_ecef(x: float, y: float, z: float, a: float, f: float) -> Tuple[float, float]:
    e2 = f * (2 - f)
    p = math.hypot(x, y)
    lon = math.atan2(y, x)
    lat = math.atan2(z, p * (1 - e2))
    for _ in range(6):
        n = a / math.sqrt(1 - e2 * math.sin(lat) ** 2)
        lat = math.atan2(z + e2 * n * math.sin(lat), p)
    return lat, lon


def ed50_utm_to_latlng(easting: float, northing: float, zone: int = 30) -> Tuple[float, float]:
    """UTM ED50 (EPSG:23030) -> (latitud, longitud) WGS84, en grados.

    Los datos abiertos del Ayuntamiento de Zaragoza (restaurantes, monumentos)
    usan el sistema antiguo ED50, no ETRS89: tratarlos como ETRS89 desplaza
    los puntos unos 250 m. Se aplica la transformación de Helmert de 7
    parámetros para la España peninsular (precisión de ~0,5 m frente a PROJ).
    """
    lat, lon = _utm_inverse(easting, northing, *_HAYFORD, zone)
    x, y, z = _to_ecef(lat, lon, *_HAYFORD)
    tx, ty, tz = -131.032, -100.251, -163.354
    arc = math.pi / 180 / 3600
    rx, ry, rz = -1.2438 * arc, -0.0195 * arc, -1.1436 * arc
    s = 1 - 9.39e-6
    x2 = tx + s * (x - rz * y + ry * z)
    y2 = ty + s * (rz * x + y - rx * z)
    z2 = tz + s * (-ry * x + rx * y + z)
    lat2, lon2 = _from_ecef(x2, y2, z2, *_WGS84)
    return round(math.degrees(lat2), 6), round(math.degrees(lon2), 6)


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
        lat, lng = ed50_utm_to_latlng(east, north)
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

    # Restaurantes: «streetAddress»; monumentos: «address».
    street = _text(raw.get("streetAddress")) or _text(raw.get("address"))
    postal = _text(raw.get("postalCode"))
    address = ", ".join(p for p in (street, postal) if p)
    if lat is None and not street:
        return None
    tel = raw.get("tel")
    phone = _text(tel.get("tel")) if isinstance(tel, dict) else _text(tel)
    url = _text(raw.get("url"))
    if url and not re.match(r"https?://", url, re.I):
        url = ""
    place = {
        "id": f"{KINDS[kind]['prefix']}-{raw.get('id')}",
        "type": kind,
        "name": name,
        "address": address,
        "street": street,
        "postal": postal,
        "locSource": "ayuntamiento" if lat is not None else "",
        "phone": phone,
        "url": url,
        "lat": lat,
        "lng": lng,
        "source": "ayuntamiento",
        "lastUpdated": datetime.now(timezone.utc).isoformat(),
    }
    if kind == "monumento":
        place.update(monument_details(raw))
    return place


# ---------------------------------------------------------------------------
# Monumentos y museos
# ---------------------------------------------------------------------------


def html_to_text(value: Any) -> str:
    """Texto legible a partir del HTML de las fichas: párrafos y listas como
    saltos de línea, sin etiquetas ni imágenes. No cambia la redacción."""
    if not isinstance(value, str):
        return ""
    text = value.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"<\s*br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"<\s*li[^>]*>", "\n• ", text, flags=re.I)
    text = re.sub(r"</\s*li\s*>", "", text, flags=re.I)
    text = re.sub(r"</\s*(p|ul|h\d)\s*>", "\n", text, flags=re.I)
    text = re.sub(r"<\s*(p|ul|h\d)[^>]*>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text).replace("\xa0", " ")
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.split("\n")]
    text = "\n".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


# Grupos de estilo para los filtros de la app, a partir del campo «estilo»
# («barroco, neoclasico», «contemporaneo: historicismo Neomudéjar»...).
STYLE_GROUPS = [
    ("Romano", ("romano",)),
    ("Medieval", ("romanico", "gotico", "bajomedieval", "medieval")),
    ("Mudéjar", ("mudejar",)),
    ("Renacentista", ("renacentista",)),
    ("Barroco", ("barroco",)),
    ("Neoclásico", ("neoclasico",)),
    ("Modernista", ("modernista",)),
    ("Contemporáneo", ("contemporaneo", "comtemporaneo", "historicismo", "regionalista", "racionalista", "eclecticismo")),
    ("Actual", ("actual",)),
    ("Naturaleza", ("entorno",)),
]


def _fold(text: str) -> str:
    text = text.lower()
    for a, b in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ú", "u"), ("ü", "u")):
        text = text.replace(a, b)
    return text


def style_groups(estilo: str) -> List[str]:
    """«barroco, neoclasico» -> ["Barroco", "Neoclásico"]. «Neomudéjar» dentro
    de un historicismo cuenta como contemporáneo, no como mudéjar."""
    folded = _fold(estilo or "")
    words = set(re.findall(r"[a-zñ]+", folded))
    groups = []
    for label, keys in STYLE_GROUPS:
        if any(key in words for key in keys):
            groups.append(label)
    return groups


def https_url(value: Any) -> str:
    url = _text(value)
    if url.startswith("http://www.zaragoza.es/"):
        url = "https://" + url[len("http://"):]
    return url if url.startswith("https://") else ""


def monument_details(raw: Dict[str, Any]) -> Dict[str, Any]:
    """Campos propios de un monumento: textos oficiales (sin HTML), época,
    estilo, foto y página oficial del Ayuntamiento."""
    estilo = _text(raw.get("estilo"))
    title = _text(raw.get("title"))
    tel = raw.get("phone")
    return {
        "description": html_to_text(raw.get("description")),
        "horario": html_to_text(raw.get("horario")),
        "price": html_to_text(raw.get("price")),
        "datacion": _text(raw.get("datacion")),
        "estilo": estilo,
        "styles": style_groups(estilo),
        "museum": bool(re.search(r"\bmuseo\b|caixaforum", title, re.I)),
        "top": raw.get("top") == "S",
        "image": https_url(raw.get("image")),
        "url": https_url(raw.get("uri")),
        "phone": _text(tel) if isinstance(tel, str) else "",
    }


# ---------------------------------------------------------------------------
# Ubicación por dirección (CartoCiudad, Instituto Geográfico Nacional)
# ---------------------------------------------------------------------------

CARTOCIUDAD_FIND = "https://www.cartociudad.es/geocoder/api/geocoder/find"
GEOCODE_VERSION = "v2"  # súbela si mejora la limpieza de direcciones: se reintenta todo
NOT_FOUND_RETRY_DAYS = 30

_ABBREVIATIONS = [
    (r"^\s*c/\s*", "Calle "), (r"^\s*cl\.?\s+", "Calle "), (r"^\s*c\.\s*", "Calle "),
    (r"^\s*avda\.?\s*", "Avenida "), (r"^\s*av\.?\s+", "Avenida "), (r"^\s*avd\.?\s*", "Avenida "),
    (r"^\s*pza\.?\s*", "Plaza "), (r"^\s*pl\.?\s+", "Plaza "), (r"^\s*p[ºo°]\.?\s*", "Paseo "),
    (r"^\s*ps\.?\s+", "Paseo "), (r"^\s*ctra\.?\s*", "Carretera "), (r"^\s*cno\.?\s*", "Camino "),
]
_ROAD_TYPES = (
    "avenida|calle|plaza|paseo|camino|carretera|ronda|via|vía|travesía|travesia|glorieta|"
    "callejón|callejon|cuesta|pasaje|urbanización|urbanizacion"
)


def clean_address(street: str) -> str:
    """Deja la dirección en el formato que entiende CartoCiudad: «Calle X 10».

    Resuelve «Gómez Avellaneda (Avenida), 43», «C/ Coso, 35 - CC. Puerta
    Cinegia», «Juslibol 2 (esquina ...)», rangos «4-6» y similares."""
    text = re.sub(r"\s+", " ", street or "").strip()
    if not text:
        return ""
    # «Nombre (Avenida), 43» -> «Avenida Nombre 43»
    m = re.match(rf"^(?P<name>.+?)\s*\((?P<kind>{_ROAD_TYPES})\)\s*,?\s*(?P<rest>.*)$", text, re.I)
    if m:
        text = f"{m.group('kind')} {m.group('name')} {m.group('rest')}".strip()
    # «... - CC. Puerta Cinegia, planta 1ª»: se corta en el guion
    text = re.split(r"\s+[-–—]\s+", text)[0]
    # paréntesis restantes: (esquina ...), (entrada por ...)
    text = re.sub(r"\([^)]*\)", " ", text)
    for pattern, replacement in _ABBREVIATIONS:
        replaced = re.sub(pattern, replacement, text, flags=re.I)
        if replaced != text:
            text = replaced
            break
    text = re.sub(r"\b(s/n|sn)\b", "", text, flags=re.I)
    text = re.sub(r"\bn[º°o]\.?\s*(?=\d)", "", text, flags=re.I)
    text = re.sub(r"(\d+)\s*[-/]\s*\d+", r"\1", text)  # rangos: 4-6 -> 4
    text = re.sub(r",?\s*(local|bajos?|planta|piso|esc\.?|portal|puestos?|cc\.?)\b.*$", "", text, flags=re.I)
    text = re.sub(r"\b0+(\d)", r"\1", text)  # 09 -> 9
    text = re.sub(r"\s*,\s*", " ", text)
    return re.sub(r"\s+", " ", text).strip(" ,")


_GENERIC_WORDS = {"calle", "avenida", "plaza", "paseo", "carretera", "camino", "zaragoza", "del", "las", "los", "por"}


def _street_words(text: str) -> set:
    text = re.sub(r"\d+", " ", text.lower())
    return {w for w in re.findall(r"[a-záéíóúüñ]{3,}", text) if w not in _GENERIC_WORDS}


def cartociudad_find(query: str) -> Optional[Dict[str, Any]]:
    """Mejor resultado de CartoCiudad para una dirección; None si no hay.
    Lanza OSError si el servicio no responde."""
    url = f"{CARTOCIUDAD_FIND}?{urllib.parse.urlencode({'q': query, 'limit': 1})}"
    request = urllib.request.Request(url, headers={"User-Agent": "ZaragozaCulturaApp/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read().decode("utf-8").strip()
    if not body:  # cuando no encuentra la dirección responde con el cuerpo vacío
        return None
    try:
        data = json.loads(body)
    except ValueError:
        return None
    return data if isinstance(data, dict) and data.get("lat") is not None else None


def geocode_address(street: str, postal: str, find=cartociudad_find) -> Optional[Tuple[float, float]]:
    """(lat, lng) a nivel de portal, o None. Solo acepta resultados que sean un
    portal concreto, del municipio de Zaragoza, dentro de su entorno y en una
    calle que se parezca a la pedida (evita aciertos en otra ciudad)."""
    address = clean_address(street)
    if not address:
        return None
    wanted = _street_words(address)
    for query in (f"{address}, {postal} Zaragoza".replace(" ,", ","), f"{address}, Zaragoza"):
        result = find(query)
        if not result:
            continue
        if result.get("type") != "portal" or result.get("noNumber"):
            continue
        if str(result.get("muni", "")).lower() != "zaragoza":
            continue
        lat, lng = float(result["lat"]), float(result["lng"])
        if not (41.3 <= lat <= 42.0 and -1.4 <= lng <= -0.5):
            continue
        if wanted and not (wanted & _street_words(str(result.get("address", "")))):
            continue
        return round(lat, 6), round(lng, 6)
    return None


def geocode_places(
    places: List[Dict[str, Any]],
    cache: Dict[str, Dict[str, Any]],
    find=cartociudad_find,
    pause=time.sleep,
    max_calls: int = 3000,
    now: Optional[datetime] = None,
) -> Dict[str, Any]:
    """Pone lat/lng a los lugares que no las traen, a partir de su dirección.

    `cache` (clave -> resultado) se actualiza para no repetir consultas; los
    «no encontrado» se reintentan a los 30 días. Devuelve estadísticas y las
    entradas nuevas de la caché para guardarlas."""
    now = now or datetime.now(timezone.utc)
    stats: Dict[str, Any] = {"placed": 0, "from_cache": 0, "not_found": 0, "errors": 0, "calls": 0}
    new_entries: Dict[str, Dict[str, Any]] = {}
    for place in places:
        if place.get("lat") is not None or not place.get("street"):
            continue
        key = f"{GEOCODE_VERSION}|{clean_address(place['street']).lower()}|{place.get('postal', '')}"
        entry = cache.get(key)
        if entry is not None:
            if entry.get("found"):
                place["lat"], place["lng"], place["locSource"] = entry["lat"], entry["lng"], "cartociudad"
                stats["placed"] += 1
                stats["from_cache"] += 1
                continue
            try:
                age = now - datetime.fromisoformat(entry.get("at", ""))
            except ValueError:
                age = timedelta(days=NOT_FOUND_RETRY_DAYS + 1)
            if age < timedelta(days=NOT_FOUND_RETRY_DAYS):
                stats["not_found"] += 1
                continue
        if stats["calls"] >= max_calls:
            break
        stats["calls"] += 1
        try:
            found = geocode_address(place["street"], place.get("postal", ""), find)
        except (OSError, ValueError):
            stats["errors"] += 1  # fallo temporal: no se guarda en la caché
            pause(1.0)
            continue
        pause(0.2)
        record: Dict[str, Any] = {"found": found is not None, "at": now.isoformat()}
        if found:
            record["lat"], record["lng"] = found
            place["lat"], place["lng"], place["locSource"] = found[0], found[1], "cartociudad"
            stats["placed"] += 1
        else:
            stats["not_found"] += 1
        cache[key] = record
        new_entries[key] = record
    stats["new_entries"] = new_entries
    return stats


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

    if len(places) < KINDS[kind]["min"]:
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
        if len(places) < KINDS[kind]["min"]:
            print(f"[ERROR] Demasiado pocos lugares '{kind}'; no se guarda nada.", file=sys.stderr)
            return 1
        from pymongo import MongoClient

        client = MongoClient(uri, serverSelectionTimeoutMS=10000)
        database = client["zaragoza_cultura"]
        # Ubicación por dirección para los que no traen coordenadas.
        cache = {doc["_id"]: doc for doc in database["geocode_cache"].find({})}
        stats = geocode_places(places, cache)
        for key, record in stats["new_entries"].items():
            database["geocode_cache"].replace_one({"_id": key}, {"_id": key, **record}, upsert=True)
        print(
            f"[OK] Ubicados por dirección: {stats['placed']} ({stats['from_cache']} de la caché, "
            f"{stats['calls']} consultas); sin resultado: {stats['not_found']}; errores: {stats['errors']}."
        )
        with_coords = sum(1 for p in places if p["lat"] is not None)
        print(f"[INFO] {kind}: {with_coords} de {len(places)} con ubicación en el mapa.")
        save(kind, places, database["places"])
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
