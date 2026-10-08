"""Descripciones propias de las actividades.

El texto de cada actividad del Ayuntamiento se reescribe (mismo contenido,
otra redacción) y se guarda en rewrites.json, indexado por una huella del
texto original: así un texto compartido por varias actividades se reescribe
una sola vez y, si el Ayuntamiento lo cambia, vuelve a quedar pendiente.

Una actividad no se publica hasta tener su texto propio. Si faltan pocos
días para que se celebre y aún no lo tiene, se publica sin descripción para
que no se pierda.
"""

from __future__ import annotations

import hashlib
import json
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

PATH = Path(__file__).with_name("rewrites.json")

# Con menos de estos días para la actividad, se publica aunque no tenga texto.
GRACE_DAYS = 3


def text_key(description: Any) -> str:
    """Huella del texto original, sin contar espacios ni saltos de línea."""
    text = " ".join(description.split()) if isinstance(description, str) else ""
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:16] if text else ""


def load(path: Path = PATH) -> Dict[str, str]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in data.items() if isinstance(v, str) and v.strip()}


# Lo que escribe el scraper cuando la actividad no trae descripción.
NO_DESCRIPTION = "Sin descripción disponible en la fuente original."


def _from_council(event: Dict[str, Any]) -> bool:
    return event.get("source", "ayuntamiento") == "ayuntamiento"


def _key(event: Dict[str, Any]) -> str:
    """Huella del texto a reescribir, o "" si la actividad no lo necesita."""
    description = event.get("description")
    if not _from_council(event) or description == NO_DESCRIPTION:
        return ""
    return text_key(description)


def with_own_text(event: Dict[str, Any], rewrites: Dict[str, str]) -> Dict[str, Any]:
    """La actividad con su texto propio (vacío si aún no lo tiene)."""
    key = _key(event)
    if key:
        return {**event, "description": rewrites.get(key, "")}
    if _from_council(event) and event.get("description") == NO_DESCRIPTION:
        return {**event, "description": ""}
    return event


def publish(
    events: Iterable[Dict[str, Any]],
    rewrites: Dict[str, str],
    today: Optional[date] = None,
) -> List[Dict[str, Any]]:
    """Las actividades que se pueden enseñar, ya con su texto propio."""
    soon = ((today or date.today()) + timedelta(days=GRACE_DAYS)).isoformat()
    out = []
    for event in events:
        key = _key(event)
        if key and key not in rewrites and str(event.get("date", ""))[:10] > soon:
            continue
        out.append(with_own_text(event, rewrites))
    return out


def pending(events: Iterable[Dict[str, Any]], rewrites: Dict[str, str]) -> List[Dict[str, str]]:
    """Textos que faltan por reescribir, uno por huella."""
    out: Dict[str, Dict[str, str]] = {}
    for event in events:
        key = _key(event)
        if key and key not in rewrites and key not in out:
            out[key] = {
                "key": key,
                "title": str(event.get("title", "")),
                "category": str(event.get("category", "")),
                "description": event["description"],
            }
    return list(out.values())


def live_keys(events: Iterable[Dict[str, Any]]) -> List[str]:
    """Huellas en uso, para poder limpiar las que ya no hacen falta."""
    return sorted({key for key in map(_key, events) if key})
