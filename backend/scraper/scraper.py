#!/usr/bin/env python3
"""Scraper para la agenda cultural del Ayuntamiento de Zaragoza.

Objetivo:
- extraer eventos de la web oficial
- normalizar los campos de la app
- generar un JSON consumible por la app Flutter

No usa dependencias externas: solo stdlib de Python.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import os
from datetime import datetime, timedelta, timezone
from hashlib import sha1
from html import unescape
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen
from pymongo import MongoClient

BASE_URL = "https://www.zaragoza.es/sede/servicio/cultura/"
DATASET_URL = "https://www.zaragoza.es/sede/servicio/data/dataset-282/_search"
DEFAULT_OUTPUT = "backend/data/zaragoza_events.json"
DATASET_FILTER = '-portales.portal.id:2 AND -portales.portal.id:24 AND -portales.portal.id:28 AND -type:("Cursos y Talleres")'

SPANISH_MONTHS = {
    "enero": "01",
    "febrero": "02",
    "marzo": "03",
    "abril": "04",
    "mayo": "05",
    "junio": "06",
    "julio": "07",
    "agosto": "08",
    "septiembre": "09",
    "octubre": "10",
    "noviembre": "11",
    "diciembre": "12",
}
WEEKDAYS = {
    "lunes": 0,
    "martes": 1,
    "miércoles": 2,
    "miercoles": 2,
    "jueves": 3,
    "viernes": 4,
    "sábado": 5,
    "sabado": 5,
    "domingo": 6,
}
CATEGORY_KEYWORDS = {
    "musica": ["música", "musica", "concierto", "festival", "auditorio"],
    "teatro": ["teatro", "escénica", "escenica", "obra", "danza"],
    "gastronomia": ["gastronomía", "gastronomia", "tapas", "degustación", "degustacion", "saborea"],
    "exposiciones": ["exposición", "exposicion", "expo", "muestra", "galería", "galeria"],
    "cine": ["cine", "película", "pelicula", "proyección", "proyeccion"],
    "conferencias": ["charla", "conferencia", "jornada", "seminario"],
    "infantil": ["infantil", "familia", "niños", "ninos", "juvenil"],
    "eventos": ["festival", "feria", "evento", "agenda", "programa"],
}
PLACE_KEYWORDS = [
    "auditorio",
    "teatro",
    "centro cívico",
    "centro civico",
    "museo",
    "plaza",
    "palacio",
    "sala",
    "biblioteca",
    "espacio",
    "casa",
    "pabellón",
    "pabellon",
    "mercado",
    "centro de historias",
]


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    text = " ".join(str(value).replace("\xa0", " ").split())
    if "Ã" in text or "Â" in text:
        try:
            text = text.encode("latin1").decode("utf-8")
        except UnicodeError:
            pass
    return text


def clean_html_to_text(raw_html: str) -> str:
    raw_html = re.sub(r"<script.*?</script>", " ", raw_html, flags=re.I | re.S)
    raw_html = re.sub(r"<style.*?</style>", " ", raw_html, flags=re.I | re.S)
    text = re.sub(r"<[^>]+>", " ", raw_html)
    text = unescape(text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def extract_more_info_url(raw_html: str, fallback_url: str) -> str:
    section_match = re.search(
        r'<[^>]+id=["\']additional-info["\'][^>]*>(.*?)(?:</div>\s*){2}',
        raw_html,
        flags=re.I | re.S,
    )
    section = section_match.group(1) if section_match else ""
    for href in re.findall(r'href=["\']([^"\']+)["\']', section, flags=re.I):
        url = urljoin(fallback_url, unescape(href)).strip()
        parsed = urlparse(url)
        if parsed.scheme in ("http", "https") and "/sede/servicio/cultura/evento/" not in parsed.path:
            return url
    return fallback_url


def fetch(url: str, timeout: int = 25) -> str:
    req = Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
        "Accept-Language": "es-ES,es;q=0.9",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    })
    with urlopen(req, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        body = response.read().decode(charset, errors="replace")
        if "Ã" in body or "Â" in body:
            try:
                body = body.encode("latin1").decode("utf-8")
            except UnicodeError:
                pass
        return body


VENUE_URL = "https://www.zaragoza.es/sede/servicio/equipamiento/{id}.json"


def is_council_url(url: str) -> bool:
    host = (urlparse(url).hostname or "").lower()
    return host == "zaragoza.es" or host.endswith(".zaragoza.es")


def external_url(value: Any) -> str:
    """La dirección si es una web ajena al Ayuntamiento; si no, ""."""
    url = normalize_text(value)
    if url and not re.match(r"https?://", url, re.I):
        url = "https://" + url
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or "." not in (parsed.hostname or ""):
        return ""
    return "" if is_council_url(url) else url


class VenueWebsites:
    """Web propia de cada lugar de realización, según su ficha de
    equipamiento. Se pregunta una sola vez por lugar en cada ejecución."""

    def __init__(self, load=None):
        self._load = load or self._download
        self._known: Dict[str, str] = {}

    @staticmethod
    def _download(venue_id: str) -> Dict[str, Any]:
        req = Request(VENUE_URL.format(id=venue_id), headers={
            "User-Agent": "ZaragozaCulturaApp/1.0",
            "Accept": "application/json",
        })
        with urlopen(req, timeout=20) as response:
            return json.loads(response.read().decode("utf-8"))

    def __call__(self, location: Any) -> str:
        venue_id = str(location.get("id") or "") if isinstance(location, dict) else ""
        if not venue_id.isdigit():
            return ""
        if venue_id not in self._known:
            try:
                self._known[venue_id] = external_url(self._load(venue_id).get("url"))
            except (HTTPError, URLError, TimeoutError, ValueError, AttributeError):
                self._known[venue_id] = ""
        return self._known[venue_id]


def fetch_json(url: str, payload: Dict[str, Any], timeout: int = 40) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = Request(url, data=body, headers={
        "User-Agent": "ZaragozaCulturaApp/1.0",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }, method="POST")
    with urlopen(req, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_public_event_ids(base_url: str, months_ahead: int = 3) -> set[str]:
    """Return event IDs rendered by the public calendar for the current month
    plus the following `months_ahead` months, so events already published for
    next month aren't dropped just because the scraper ran earlier."""
    import os
    from playwright.sync_api import sync_playwright

    # Intentamos usar el Chrome local en Windows, si no existe o estamos en Linux, usamos el de Playwright
    local_chrome_path = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

    with sync_playwright() as playwright:
        launch_args = {
            "headless": True,
            "args": ["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"]
        }
        if os.name == 'nt' and os.path.exists(local_chrome_path):
            launch_args["executable_path"] = local_chrome_path

        browser = playwright.chromium.launch(**launch_args)
        page = browser.new_page(locale="es-ES")
        try:
            last_error: Exception | None = None
            for attempt in range(3):
                try:
                    page.goto(base_url, wait_until="domcontentloaded", timeout=120000)
                    page.locator("#selected-day").wait_for(state="visible", timeout=60000)
                    last_error = None
                    break
                except Exception as exc:  # noqa: BLE001 - retry on any transient nav failure
                    last_error = exc
                    print(f"[WARN] Intento {attempt + 1}/3 de cargar el calendario fallo: {exc}", file=sys.stderr)
                    page.wait_for_timeout(3000)
            if last_error is not None:
                raise last_error
            public_ids: set[str] = set()
            for month_offset in range(months_ahead + 1):
                days = page.locator("#calendarV2 .calendar-dates .day")
                for index in range(days.count()):
                    days.nth(index).click()
                    page.wait_for_timeout(150)
                    links = page.locator("#selected-day a[href*='/sede/servicio/cultura/evento/']").evaluate_all(
                        "elements => elements.map(element => element.href)"
                    )
                    public_ids.update(
                        match.group(1)
                        for link in links
                        if (match := re.search(r"/evento/(\d+)$", link))
                    )
                if month_offset < months_ahead:
                    page.locator("#calendar_next").click()
                    page.wait_for_timeout(300)
            return public_ids
        finally:
            browser.close()


def fetch_dataset(from_date: datetime, to_date: datetime) -> List[Dict[str, Any]]:
    payload = fetch_json(DATASET_URL, {
        "from": 0,
        "size": 3000,
        "query": {
            "bool": {
                "must": [
                    {"range": {"startDate": {"to": to_date.strftime("%Y-%m-%d"), "include_lower": True, "include_upper": True, "boost": 1}}},
                    {"range": {"endDate": {"from": from_date.strftime("%Y-%m-%d"), "include_lower": True, "include_upper": True, "boost": 1}}},
                    {"query_string": {"query": DATASET_FILTER}},
                ],
            },
        },
    })
    return [hit.get("_source", {}) for hit in payload.get("hits", {}).get("hits", [])]


def extract_json_ld_blocks(raw_html: str) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    matches = re.findall(r"<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>", raw_html, flags=re.I | re.S)
    for block in matches:
        try:
            data = json.loads(unescape(block))
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            items.append(data)
        elif isinstance(data, list):
            items.extend([item for item in data if isinstance(item, dict)])
    return items


def find_first_event_like(data: Any) -> Optional[Dict[str, Any]]:
    if isinstance(data, dict):
        if data.get("@type") == "Event" or (isinstance(data.get("@type"), list) and "Event" in data.get("@type")):
            return data
        if "@graph" in data and isinstance(data["@graph"], list):
            for item in data["@graph"]:
                result = find_first_event_like(item)
                if result:
                    return result
        return None
    if isinstance(data, list):
        for item in data:
            result = find_first_event_like(item)
            if result:
                return result
    return None


def coerce_date(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (int, float)):
        try:
            dt = datetime.fromtimestamp(value / 1000)
            return dt.strftime("%Y-%m-%d")
        except Exception:
            return ""
    text = normalize_text(value)
    if not text:
        return ""
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return text
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T.*", text):
        return text.split("T")[0]
    match = re.search(r"(\d{1,2})\s+de\s+([a-zA-Z]+)\s+de\s+(\d{4})", text)
    if match:
        day, month, year = match.groups()
        month_key = month.lower()
        month_number = SPANISH_MONTHS.get(month_key)
        if month_number:
            return f"{year}-{month_number}-{int(day):02d}"
    match = re.search(r"(\d{4})-(\d{2})-(\d{2})", text)
    if match:
        return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"
    return ""


def coerce_time(value: Any) -> str:
    if value is None:
        return ""
    text = normalize_text(value)
    if not text:
        return ""
    match = re.search(r"(\d{1,2}:\d{2})", text)
    if match:
        return match.group(1)
    return ""


def extract_title_from_html(raw_html: str) -> str:
    match = re.search(r"<h1[^>]*>(.*?)</h1>", raw_html, flags=re.I | re.S)
    if match:
        text = clean_html_to_text(match.group(1))
        if text:
            return text
    title_match = re.search(r"<title>(.*?)</title>", raw_html, flags=re.I | re.S)
    if title_match:
        text = clean_html_to_text(title_match.group(1))
        if text:
            return text.replace("Zaragoza", "").strip(" -")
    return ""


def pick_description(raw_html: str, candidate: str = "") -> str:
    if candidate:
        return candidate
    paragraphs = re.findall(r"<p[^>]*>(.*?)</p>", raw_html, flags=re.I | re.S)
    for block in paragraphs:
        text = clean_html_to_text(block)
        if len(text) >= 40:
            return text
    return ""


def pick_place(raw_html: str, fallback: str = "") -> str:
    if fallback:
        return fallback
    text = clean_html_to_text(raw_html)
    for keyword in PLACE_KEYWORDS:
        m = re.search(rf"([A-ZÁÉÍÓÚÑa-záéíóúñ0-9.\s\-/()]+(?:{keyword}|{keyword.title()}|{keyword.upper()}))", text, flags=re.I)
        if m and len(m.group(1)) > 4:
            value = m.group(1).strip(" -")
            if len(value) < 120:
                return value
    return ""


def detect_category(text: str, url: str) -> str:
    normalized = text.lower()
    for category, keywords in CATEGORY_KEYWORDS.items():
        if any(keyword.lower() in normalized for keyword in keywords):
            return category
    if "/musica" in url.lower() or "música" in normalized:
        return "musica"
    if "/teatro" in url.lower() or "teatro" in normalized:
        return "teatro"
    if "/evento" in url.lower():
        return "eventos"
    return "eventos"


def dataset_date(value: Any) -> Optional[datetime]:
    text = normalize_text(value)
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        return None


def coordinates_of(obj: Any) -> Optional[tuple]:
    """(latitud, longitud) de un objeto del dataset con `geometry`, o None.

    El dataset usa GeoJSON: las coordenadas vienen como [longitud, latitud].
    """
    geometry = obj.get("geometry") if isinstance(obj, dict) else None
    coords = geometry.get("coordinates") if isinstance(geometry, dict) else None
    if not isinstance(coords, (list, tuple)) or len(coords) < 2:
        return None
    try:
        lng, lat = float(coords[0]), float(coords[1])
    except (TypeError, ValueError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return None
    return (round(lat, 6), round(lng, 6))


def is_free(source: Dict[str, Any]) -> bool:
    """¿El Ayuntamiento indica que la actividad es gratuita?

    Solo es True cuando el acto publica sus tarifas y todas valen 0 € (o son
    del grupo «Gratuita»). Si no publica precio no se sabe, y se devuelve False:
    el filtro «Gratis» de la app solo enseña las gratuitas confirmadas."""
    fares = source.get("price")
    if not isinstance(fares, list) or not fares:
        return False
    for fare in fares:
        if not isinstance(fare, dict):
            return False
        group = normalize_text(fare.get("fareGroup")).lower()
        value = fare.get("hasCurrencyValue")
        if group.startswith("gratuit") and not value:
            continue
        if isinstance(value, (int, float)) and not isinstance(value, bool) and value == 0:
            continue
        return False
    return True


def dataset_event_occurrences(
    source: Dict[str, Any],
    limit: int,
    public_ids: Optional[set[str]] = None,
    venue_website=None,
) -> List[Dict[str, Any]]:
    source_id = str(source.get("id", ""))
    if public_ids is not None and source_id not in public_ids:
        return []
    title = normalize_text(source.get("title"))
    if not title:
        return []
    official_url = normalize_text(source.get("alt"))
    if not re.match(r"https://www\.zaragoza\.es/sede/servicio/cultura/evento/\d+$", official_url):
        official_url = f"https://www.zaragoza.es/sede/servicio/cultura/evento/{source.get('id')}"
    more_info_url = normalize_text(source.get("moreInfoUrl")) or official_url
    # Las páginas generales del portal (zaragoza.es/sede/portal/...) no
    # informan de la actividad: se enlaza mejor la ficha de la agenda.
    if re.match(r"https?://(www\.)?zaragoza\.es/sede/portal", more_info_url, re.I):
        more_info_url = official_url

    description = clean_html_to_text(normalize_text(source.get("description")))
    category_text = " ".join(
        [title, description, normalize_text(source.get("type"))]
        + [normalize_text(item.get("title")) for item in source.get("category", []) if isinstance(item, dict)]
    )
    category = detect_category(category_text, official_url)
    free = is_free(source)
    output: List[Dict[str, Any]] = []
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    horizon = today + timedelta(days=366)

    for sub_event in source.get("subEvent") or [source]:
        if not isinstance(sub_event, dict):
            continue
        start = dataset_date(sub_event.get("startDate") or source.get("startDate"))
        end = dataset_date(sub_event.get("endDate") or source.get("endDate")) or start
        if not start or not end or end < today or start > horizon:
            continue
        location = sub_event.get("location") or {}
        place = normalize_text(location.get("title") if isinstance(location, dict) else location) or normalize_text(source.get("location"))
        coords = coordinates_of(location) or coordinates_of(source)
        # Si la actividad no tiene enlace propio y se celebra en un lugar con
        # web (un teatro o una sala privados), «Más información» lleva allí.
        info_url = more_info_url
        if venue_website and is_council_url(more_info_url):
            info_url = venue_website(location) or more_info_url
        hours_by_day: Dict[int, List[Dict[str, Any]]] = {}
        for opening in sub_event.get("openingHours", []):
            if not isinstance(opening, dict):
                continue
            weekday = WEEKDAYS.get(normalize_text(opening.get("dayOfWeek")).lower())
            if weekday is not None:
                hours_by_day.setdefault(weekday, []).append(opening)

        current = max(start, today)
        while current.date() <= end.date() and len(output) < limit:
            openings = hours_by_day.get(current.weekday(), [])
            if not openings and not hours_by_day:
                # El acto no publica ningún horario: se muestra el día sin hora.
                # Si publica horarios por días, los días sin sesión (p. ej. el
                # lunes en un museo que cierra) NO son actividad ese día.
                openings = [{"startTime": ""}]
            for opening in openings:
                time_value = normalize_text(opening.get("startTime"))
                event_date = current.strftime("%Y-%m-%d")
                event_id = sha1(f"{source.get('id')}|{sub_event.get('id')}|{event_date}|{time_value}".encode("utf-8")).hexdigest()
                output.append({
                    "id": event_id,
                    "title": title,
                    "description": description or "Sin descripción disponible en la fuente original.",
                    "category": category,
                    "date": event_date,
                    "time": time_value,
                    "place": place,
                    "address": normalize_text(location.get("streetAddress")) if isinstance(location, dict) else "",
                    "officialUrl": official_url,
                    "moreInfoUrl": info_url,
                    "officialWebsite": normalize_text(source.get("url")),
                    "imageUrl": normalize_text(source.get("image")),
                    "source": "ayuntamiento",
                    "sourceId": str(source.get("id", "")),
                    "free": free,
                    "endDate": event_date,
                    # Duración total del acto (no de este día): la app lo usa
                    # para dejar al final las actividades de larga duración.
                    "lat": coords[0] if coords else None,
                    "lng": coords[1] if coords else None,
                    "runStartDate": start.strftime("%Y-%m-%d"),
                    "runEndDate": end.strftime("%Y-%m-%d"),
                    "endTime": normalize_text(opening.get("endTime")),
                    "lastUpdated": now_iso(),
                })
            current += timedelta(days=1)
    return output


def parse_event_from_detail(url: str, raw_html: str) -> Dict[str, Any]:
    full_text = clean_html_to_text(raw_html)
    title = ""
    description = ""
    date_value = ""
    time_value = ""
    place_value = ""
    category_value = "eventos"

    json_ld_entries = extract_json_ld_blocks(raw_html)
    event_ld = find_first_event_like(json_ld_entries)
    if event_ld:
        title = normalize_text(event_ld.get("name") or event_ld.get("headline") or event_ld.get("title"))
        description = normalize_text(event_ld.get("description"))
        date_value = coerce_date(event_ld.get("startDate") or event_ld.get("datePublished"))
        time_value = coerce_time(event_ld.get("startDate") or event_ld.get("doorTime"))
        place_candidate = event_ld.get("location")
        if isinstance(place_candidate, dict):
            place_value = normalize_text(place_candidate.get("name") or place_candidate.get("address", {}).get("streetAddress"))
        category_value = detect_category(full_text + " " + title + " " + description, url)

    if not title:
        title = extract_title_from_html(raw_html)
    if not description:
        description = pick_description(raw_html, description)
    if not date_value:
        for pattern in [
            r"(\d{1,2}\s+de\s+[A-Za-zÁÉÍÓÚáéíóúñÑ]+\s+de\s+\d{4})",
            r"(\d{1,2}[-/]\d{1,2}[-/]\d{4})",
            r"(\d{4}-\d{2}-\d{2})",
        ]:
            match = re.search(pattern, full_text, flags=re.I)
            if match:
                date_value = coerce_date(match.group(1))
                break
    if not time_value:
        time_match = re.search(r"(\d{1,2}:\d{2})", full_text)
        if time_match:
            time_value = time_match.group(1)
    if not place_value:
        place_value = pick_place(raw_html)

    title = title or "Evento cultural"
    description = description or "Sin descripción disponible en la fuente original."
    title = normalize_text(title)
    description = normalize_text(description)
    place_value = normalize_text(place_value)
    category_value = detect_category(f"{title} {description} {full_text}", url)

    event_id = sha1(f"{url}|{title}|{date_value or 'unknown'}".encode("utf-8")).hexdigest()

    return {
        "id": event_id,
        "title": title,
        "description": description,
        "category": category_value,
        "date": date_value,
        "time": time_value,
        "place": place_value,
        "officialUrl": url,
        "source": "ayuntamiento",
        "lastUpdated": now_iso(),
    }


def extract_event_links(raw_html: str, base_url: str) -> List[str]:
    urls = set()
    pattern = r'href=["\']((?:https?://[^"\']+)?/sede/servicio/cultura/evento/\d+/?)["\']'
    for href in re.findall(pattern, raw_html, flags=re.I):
        absolute = urljoin(base_url, href)
        if not absolute.startswith("http"):
            continue
        parsed = urlparse(absolute)
        if not re.fullmatch(r"/sede/servicio/cultura/evento/\d+/?", parsed.path):
            continue
        urls.add(absolute)
    return sorted(urls)


def collect_events(base_url: str, limit: int = 200) -> List[Dict[str, Any]]:
    try:
        dataset_events: List[Dict[str, Any]] = []
        current_date = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        months_ahead = 3
        from_date = current_date
        to_date = current_date + timedelta(days=30 * (months_ahead + 1))
        try:
            public_ids = fetch_public_event_ids(base_url, months_ahead=months_ahead)
            print(f"[OK] {len(public_ids)} fichas publicadas en el calendario visible", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001 - calendar check is a nice-to-have, not a hard requirement
            public_ids = None
            print(f"[WARN] No se pudo verificar el calendario público, se usara el dataset sin filtrar: {exc}", file=sys.stderr)
        public_sources = fetch_dataset(from_date, to_date)
        venue_website = VenueWebsites()
        for source in public_sources:
            try:
                detail_html = fetch(source.get("alt") or "")
                source["moreInfoUrl"] = extract_more_info_url(detail_html, source.get("alt") or "")
            except (HTTPError, URLError, TimeoutError, ValueError):
                source["moreInfoUrl"] = source.get("alt") or ""
            dataset_events.extend(dataset_event_occurrences(source, limit, public_ids, venue_website))
        # Enlace a la página propia del acto en la web de cada lugar apuntado
        # en venue_agendas.json. Si falla, se quedan los enlaces que había.
        try:
            import venue_links

            exact = venue_links.apply(dataset_events)
            print(f"[OK] {exact} sesiones enlazan a la página de su acto en la web del lugar", file=sys.stderr)
        except Exception as exc:  # noqa: BLE001 - es una mejora, no puede tumbar la descarga
            print(f"[WARN] No se pudieron afinar los enlaces de los lugares: {exc}", file=sys.stderr)
        dataset_events.sort(key=lambda event: (event["date"], event["time"], event["title"]))
        if dataset_events:
            return dataset_events[:limit]
    except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"No se pudo verificar el calendario público: {exc}") from exc

    home_html = fetch(base_url)
    event_links = extract_event_links(home_html, base_url)
    seen = set()
    events: List[Dict[str, Any]] = []

    for index, event_url in enumerate(event_links[:limit]):
        if event_url in seen:
            continue
        seen.add(event_url)
        try:
            event_html = fetch(event_url)
            event = parse_event_from_detail(event_url, event_html)
            if not event["date"] and not event["title"]:
                continue
            events.append(event)
            time.sleep(0.4)
        except (HTTPError, URLError, ValueError, TimeoutError) as exc:
            print(f"[WARN] No se pudo procesar {event_url}: {exc}", file=sys.stderr)
        if len(events) >= limit:
            break

    return events


def save_to_mongodb(data: List[Dict[str, Any]]) -> None:
    uri = os.environ.get("MONGODB_URI")
    if not uri:
        print("[ERROR] MONGODB_URI no configurada en las variables de entorno", file=sys.stderr)
        # Fallback to local file for development if needed, or just fail
        write_json(data, DEFAULT_OUTPUT)
        print(f"[WARN] Guardado en archivo local como fallback: {DEFAULT_OUTPUT}")
        return

    try:
        client = MongoClient(uri)
        db = client["zaragoza_cultura"]
        collection = db["events"]

        for event in data:
            # Usamos el id (hash SHA1) como filtro para evitar duplicados
            collection.update_one(
                {"id": event["id"]},
                {"$set": event},
                upsert=True
            )
        print(f"[OK] {len(data)} eventos sincronizados con MongoDB Atlas.")
        remove_stale_events(collection, data)
        remove_past_events(collection, data)
        client.close()
    except Exception as exc:
        print(f"[ERROR] Fallo al conectar con MongoDB: {exc}", file=sys.stderr)
        write_json(data, DEFAULT_OUTPUT)
        print(f"[WARN] Guardado en archivo local como fallback: {DEFAULT_OUTPUT}")

def remove_stale_events(collection, data: List[Dict[str, Any]]) -> None:
    """Borra actividades futuras que la fuente ya no publica.

    Sin esto, un error corregido del scraper (o un acto cancelado) dejaría
    para siempre las entradas antiguas en la base de datos. Salvaguardas: solo
    toca actividades del Ayuntamiento con fecha de hoy en adelante, no actúa
    si la extracción trajo pocos eventos y se detiene si borraría demasiado.
    """
    if len(data) < 1000:
        print("[INFO] Limpieza omitida: la extracción trajo pocos eventos.")
        return
    today = datetime.now().strftime("%Y-%m-%d")
    fresh_ids = {event["id"] for event in data}
    query = {"source": "ayuntamiento", "date": {"$gte": today}}
    existing = collection.count_documents(query)
    stale_ids = [doc["id"] for doc in collection.find(query, {"id": 1, "_id": 0}) if doc["id"] not in fresh_ids]
    if not stale_ids:
        print("[OK] Limpieza: no hay entradas obsoletas.")
        return
    if existing and len(stale_ids) > 0.4 * existing:
        print(f"[WARN] Limpieza cancelada: borraría {len(stale_ids)} de {existing} (demasiado).")
        return
    for i in range(0, len(stale_ids), 500):
        collection.delete_many({"id": {"$in": stale_ids[i:i + 500]}})
    print(f"[OK] Limpieza: {len(stale_ids)} entradas obsoletas eliminadas de {existing}.")


PAST_EVENTS_KEEP_DAYS = 7


def remove_past_events(collection, data: List[Dict[str, Any]]) -> None:
    """Borra actividades del Ayuntamiento de hace más de una semana.

    Mantiene la base de datos pequeña (el plan gratuito de Atlas es limitado).
    Se conserva una semana de margen y no actúa si la extracción trajo pocos
    eventos, por si la fuente hubiera fallado.
    """
    if len(data) < 1000:
        print("[INFO] Purga de pasados omitida: la extracción trajo pocos eventos.")
        return
    limit = (datetime.now() - timedelta(days=PAST_EVENTS_KEEP_DAYS)).strftime("%Y-%m-%d")
    result = collection.delete_many({"source": "ayuntamiento", "date": {"$lt": limit}})
    print(f"[OK] Purga: {result.deleted_count} actividades anteriores a {limit} eliminadas.")


def write_json(data: List[Dict[str, Any]], output_path: str) -> None:
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scraper de agenda cultural del Ayuntamiento de Zaragoza")
    parser.add_argument("--base-url", default=BASE_URL, help="URL base de la agenda cultural")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Ruta del JSON final de salida")
    parser.add_argument("--limit", type=int, default=10000, help="Máximo de ocurrencias a procesar")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        events = collect_events(args.base_url, limit=args.limit)
        save_to_mongodb(events)
        print(f"[OK] {len(events)} eventos extraídos y procesados.")
        return 0
    except Exception as exc:  # pragma: no cover - para diagnóstico en producción
        print(f"[ERROR] Fallo general del scraper: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
