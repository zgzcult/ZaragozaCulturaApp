"""Correcciones a mano del enlace «Más información».

link_overrides.json recoge lo que se decide al revisar los enlaces:

    links          enlace fijo de una actividad (por su código del Ayuntamiento)
    no_link        actividades que no deben llevar enlace
    blocked_hosts  webs a las que nunca se enlaza: la actividad queda sin enlace
    home_only      webs que solo admiten enlaces a su portada: {web: portada}
    hidden         actividades que no se publican
    pending        sin página propia todavía; se repasan en la siguiente revisión

Se aplican al entregar la agenda, por encima de lo que haya guardado la
descarga, así que un cambio aquí se ve en cuanto se despliega el servidor.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from urllib.parse import urlparse

PATH = Path(__file__).with_name("link_overrides.json")


def load(path: Optional[Path] = None) -> Dict[str, Any]:
    try:
        data = json.loads((path or PATH).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    return {
        "links": {str(k): str(v) for k, v in (data.get("links") or {}).items() if str(v).startswith("http")},
        "no_link": {str(x) for x in data.get("no_link") or []},
        "blocked_hosts": {_bare(str(x)) for x in data.get("blocked_hosts") or []},
        "home_only": {
            _bare(str(k)): str(v) for k, v in (data.get("home_only") or {}).items() if str(v).startswith("http")
        },
        "hidden": {str(x) for x in data.get("hidden") or []},
        "pending": {str(x) for x in data.get("pending") or []},
    }


def _bare(host: str) -> str:
    return host.strip().lower().removeprefix("www.")


def host_of(url: str) -> str:
    return _bare(urlparse(url).hostname or "")


def apply(events: Iterable[Dict[str, Any]], overrides: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Las actividades que se publican, con su enlace definitivo. Las que se
    quedan sin enlace llevan `hideLink` para que la app no enseñe el botón."""
    out = []
    for event in events:
        code = str(event.get("sourceId") or "")
        if code and code in overrides["hidden"]:
            continue
        url = overrides["links"].get(code) or str(event.get("moreInfoUrl") or event.get("officialUrl") or "")
        # Hay webs cuyo aviso legal solo permite enlazar a la portada.
        url = overrides["home_only"].get(host_of(url), url)
        hide = code in overrides["no_link"] or not url or host_of(url) in overrides["blocked_hosts"]
        out.append({**event, "moreInfoUrl": "" if hide else url, "hideLink": hide})
    return out
