"""«Servicios útiles»: farmacias de guardia y bibliotecas municipales (datos
del Ayuntamiento de Zaragoza) y centros de salud públicos (Servicio Aragonés
de Salud y Gobierno de Aragón).

El servidor descarga las farmacias de guardia y los horarios de las
bibliotecas directamente (con caché), así están siempre al día sin depender
del workflow.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "scraper"))
from places import _coordinates, _text, html_to_text  # noqa: E402

BASE = "https://www.zaragoza.es/sede/servicio"
HEADERS = {"User-Agent": "ZaragozaCulturaApp/1.0", "Accept": "application/json"}

# Grupos en el orden en que se muestran.
GROUPS = [
    {"id": "farmacias-guardia", "title": "Farmacias de guardia", "source": "farmacia"},
    {"id": "centros-salud", "title": "Centros Salud Públicos", "source": "centros_salud"},
    {"id": "bibliotecas", "title": "Bibliotecas municipales", "source": "bibliotecas"},
]

# Centros de salud públicos de Zaragoza capital: Sector II del listado del
# Servicio Aragonés de Salud y sectores I y III de Aragón Open Data (ver
# «sources» en el fichero). Cambian muy poco.
CENTROS_SALUD_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "centros_salud.json")


def health_centres(path: str = CENTROS_SALUD_FILE) -> List[Dict[str, Any]]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    sources = data.get("sources", {})
    items = []
    for i, centre in enumerate(data.get("centros", [])):
        if centre.get("town") != "Zaragoza":  # solo Zaragoza capital y sus barrios
            continue
        source = sources.get(centre.get("source", ""), {})
        citas = source.get("citas", "")
        address = ", ".join(
            p for p in (centre.get("address", ""), f"{centre.get('postal', '')} {centre.get('town', '')}".strip()) if p
        )
        info = [
            f"Sector Zaragoza {centre['sector']}" if centre.get("sector") else "",
            f"Cita previa: {citas}" if citas else "",
            f"Atención a domicilio: {centre['home']}" if centre.get("home") else "",
        ]
        items.append(
            {
                "id": f"centros-salud-{i}",
                "name": centre["name"],
                "address": address,
                "phone": centre.get("phone", ""),
                "call": first_phone(centre.get("phone", "")),
                "horario": "",
                "info": "\n".join(x for x in info if x),
                "url": source.get("url", ""),
                "lat": None,
                "lng": None,
            }
        )
    return items

# Bibliotecas Públicas Municipales: listado y ficha oficial de cada una (ver
# «source» en el fichero). El horario se pide en vivo a la ficha oficial,
# porque cambia con las estaciones.
BIBLIOTECAS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bibliotecas.json")


def libraries(
    fetch: Callable[[str], Any],
    path: str = BIBLIOTECAS_FILE,
    workers: int = 8,
) -> List[Dict[str, Any]]:
    """Bibliotecas con su horario oficial. Si la ficha de alguna no responde,
    se muestra igual, sin horario."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("bibliotecas", [])

    def schedule(entry: Dict[str, Any]) -> str:
        try:
            record = fetch(f"{BASE}/equipamiento/{entry['id']}.json")
        except (OSError, ValueError):
            return ""
        return html_to_text(record.get("horario")) if isinstance(record, dict) else ""

    with ThreadPoolExecutor(max_workers=workers) as pool:
        schedules = list(pool.map(schedule, entries))

    items = []
    for entry, horario in zip(entries, schedules):
        address = ", ".join(
            p for p in (entry.get("address", ""), f"{entry.get('postal', '')} {entry.get('town', '')}".strip()) if p
        )
        items.append(
            {
                "id": f"bibliotecas-{entry['id']}",
                "name": entry["name"],
                "address": address,
                "phone": entry.get("phone", ""),
                "call": first_phone(entry.get("phone", "")),
                "horario": horario,
                "info": "",
                "url": f"{BASE}/equipamiento/{entry['id']}",
                "lat": None,
                "lng": None,
            }
        )
    return sorted(items, key=lambda i: i["name"].lower())


_PHONE = re.compile(r"(?<![\d])([6789](?:[ .]?\d){8})(?![\d])")


def first_phone(text: str) -> str:
    """Primer teléfono español de 9 cifras del texto («092 976 724100» ->
    «976724100»), o "" si no hay."""
    match = _PHONE.search(text or "")
    return re.sub(r"\D", "", match.group(1)) if match else ""


def _phone_text(raw: Dict[str, Any]) -> str:
    for key in ("tel", "telefonos"):
        value = raw.get(key)
        if isinstance(value, dict):
            value = value.get("tel")
        text = _text(value)
        if text:
            return text
    return ""


def _https(url: str) -> str:
    url = _text(url)
    if url.startswith("http://www.zaragoza.es/"):
        url = "https://" + url[len("http://"):]
    return url if url.startswith("https://") else ""


def normalize_service(group: str, raw: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    name = _text(raw.get("title"))
    if not name:
        return None
    lat, lng = _coordinates(raw)
    phone = _phone_text(raw)
    info: List[str] = []
    guardia = raw.get("guardia")
    if isinstance(guardia, dict):
        hours = _text(guardia.get("horario"))
        info += [f"De guardia: {hours}" if hours else "", _text(guardia.get("sector"))]
    price = html_to_text(raw.get("precio"))
    if price:
        info.append(price)
    return {
        "id": f"{group}-{raw.get('id')}",
        "name": name,
        "address": _text(raw.get("calle")),
        "phone": phone,
        "call": first_phone(phone),
        "horario": html_to_text(raw.get("horario")),
        "info": "\n".join(i for i in info if i),
        "url": _https(raw.get("link") or raw.get("uri") or ""),
        "lat": lat,
        "lng": lng,
    }


def _fetch_json(url: str) -> Any:
    request = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def _farmacias(fetch: Callable[[str], Any]) -> List[Dict[str, Any]]:
    data = fetch(f"{BASE}/farmacia.json?rows=100")
    return list(data.get("result") or []) if isinstance(data, dict) else []


def collect_services(fetch: Callable[[str], Any] = _fetch_json) -> Dict[str, Any]:
    """Todos los grupos. Si un grupo falla, se devuelve vacío y con
    `error: true`, sin estropear los demás."""
    groups = []
    for group in GROUPS:
        entry: Dict[str, Any] = {"id": group["id"], "title": group["title"], "items": []}
        try:
            if group.get("source") == "centros_salud":
                entry["items"] = sorted(health_centres(), key=lambda i: i["name"].lower())
                groups.append(entry)
                continue
            if group.get("source") == "bibliotecas":
                entry["items"] = libraries(fetch)
                groups.append(entry)
                continue
            seen = set()
            for raw in _farmacias(fetch):
                item = normalize_service(group["id"], raw)
                if item and item["id"] not in seen:
                    seen.add(item["id"])
                    entry["items"].append(item)
            entry["items"].sort(key=lambda i: i["name"].lower())
        except (OSError, ValueError) as exc:
            print(f"[WARN] Servicios '{group['id']}': {exc}")
            entry["error"] = True
        groups.append(entry)
    return {"updated": datetime.now(timezone.utc).isoformat(), "groups": groups}
