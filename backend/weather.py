"""Temperatura actual en Zaragoza, de AEMET OpenData.

La clave se lee de la variable de entorno AEMET_API_KEY (en Render), nunca
del código ni de la app. Fuente: © AEMET, «Información elaborada por la
Agencia Estatal de Meteorología».
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, Optional

STATION = "9434"  # Zaragoza Aeropuerto
STATION_NAME = "Zaragoza Aeropuerto"
OBSERVATION_URL = f"https://opendata.aemet.es/opendata/api/observacion/convencional/datos/estacion/{STATION}"


def _get_json(url: str, api_key: str = "") -> Any:
    headers = {"Accept": "application/json", "User-Agent": "ZaragozaCulturaApp/1.0"}
    if api_key:
        headers["api_key"] = api_key
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as response:
        raw = response.read()
    # AEMET entrega algunos datos en ISO-8859-15.
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
    return json.loads(text)


def latest_temperature(observations: Any) -> Optional[Dict[str, Any]]:
    """Última observación con temperatura: {"temp": 17, "time": "..."}."""
    if not isinstance(observations, list):
        return None
    for item in sorted(
        (o for o in observations if isinstance(o, dict)),
        key=lambda o: str(o.get("fint", "")),
        reverse=True,
    ):
        ta = item.get("ta")
        if isinstance(ta, (int, float)):
            return {"temp": round(ta), "time": str(item.get("fint", ""))}
    return None


def current_weather(
    api_key: Optional[str] = None,
    get_json: Callable[..., Any] = _get_json,
) -> Dict[str, Any]:
    """{"temp": 17, "time": ..., "station": ..., "source": "AEMET"}, o con
    "temp": None si no hay clave o AEMET no responde."""
    key = (os.environ.get("AEMET_API_KEY", "") if api_key is None else api_key).strip()
    result: Dict[str, Any] = {"temp": None, "time": "", "station": STATION_NAME, "source": "AEMET"}
    if not key:
        return result
    try:
        # AEMET responde primero con un enlace a los datos («datos»).
        meta = get_json(OBSERVATION_URL, key)
        url = meta.get("datos") if isinstance(meta, dict) else None
        if not isinstance(url, str) or not url.startswith("https://"):
            return result
        latest = latest_temperature(get_json(url))
        if latest:
            result.update(latest)
    except urllib.error.HTTPError as exc:
        if exc.code in (401, 403):
            # La clave de AEMET caduca cada 3 meses: hay que pedir otra en
            # opendata.aemet.es y cambiar AEMET_API_KEY en Render.
            print("[WARN] AEMET: la clave ha caducado o no es válida. Pide una nueva y actualiza AEMET_API_KEY en Render.")
            result["error"] = "clave"
        else:
            print(f"[WARN] AEMET: HTTP {exc.code}")
    except (OSError, ValueError) as exc:
        print(f"[WARN] AEMET: {exc}")
    return result
