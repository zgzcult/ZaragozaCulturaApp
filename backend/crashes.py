"""Informes de errores de la app (cierres inesperados y fallos internos).

La app envía solo datos técnicos: el mensaje de error, la traza, la versión de
la app y la del sistema. Sin identificadores del usuario ni del dispositivo.
Cada error distinto se guarda una vez en MongoDB (colección `crashes`) con un
contador, y se avisa por correo solo la primera vez que aparece.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Optional, Tuple

import submissions

MAX_ERROR = 500
MAX_STACK = 6000
MAX_FIELD = 60
MAX_BODY_BYTES = 12_000
RATE_LIMIT = 20  # informes por IP y hora


def _clean(value: Any, limit: int) -> str:
    text = value if isinstance(value, str) else ""
    text = "".join(ch for ch in text if ch in "\n\t" or ord(ch) >= 32)
    return text.strip()[:limit]


def signature(error: str, stack: str) -> str:
    """Huella del error: mismo fallo en el mismo sitio -> misma huella. Se
    quitan los números (líneas, direcciones) para que no cambie con ellos."""
    first_frames = "\n".join(stack.splitlines()[:4])
    base = re.sub(r"\d+", "#", f"{error}\n{first_frames}")
    return hashlib.sha1(base.encode("utf-8")).hexdigest()[:16]


def validate(payload: Any) -> Optional[Dict[str, str]]:
    if not isinstance(payload, dict):
        return None
    error = _clean(payload.get("error"), MAX_ERROR)
    if len(error) < 3:
        return None
    stack = _clean(payload.get("stack"), MAX_STACK)
    return {
        "error": error,
        "stack": stack,
        "appVersion": _clean(payload.get("appVersion"), MAX_FIELD),
        "platform": _clean(payload.get("platform"), MAX_FIELD),
        "osVersion": _clean(payload.get("osVersion"), MAX_FIELD),
        "signature": signature(error, stack),
    }


def store_in_mongo(report: Dict[str, str]) -> Optional[bool]:
    """Suma una aparición del error. Devuelve True si es la primera vez que
    se ve, False si ya existía y None si no se pudo guardar."""
    uri = os.environ.get("MONGODB_URI")
    if not uri:
        return None
    try:
        from pymongo import MongoClient

        client = MongoClient(uri, serverSelectionTimeoutMS=5000)
        now = datetime.now(timezone.utc).isoformat()
        result = client["zaragoza_cultura"]["crashes"].update_one(
            {"signature": report["signature"]},
            {
                "$inc": {"count": 1},
                "$set": {"lastSeen": now, "lastAppVersion": report["appVersion"]},
                "$setOnInsert": {
                    "error": report["error"],
                    "stack": report["stack"],
                    "platform": report["platform"],
                    "osVersion": report["osVersion"],
                    "firstSeen": now,
                },
            },
            upsert=True,
        )
        client.close()
        return result.upserted_id is not None
    except Exception as exc:  # no debe tumbar el servidor
        print(f"[WARN] No se pudo guardar el informe de error: {exc}")
        return None


def build_email(report: Dict[str, str]) -> Tuple[str, str]:
    lines = [
        f"Error: {report['error']}",
        f"Versión de la app: {report['appVersion'] or 'desconocida'}",
        f"Sistema: {report['platform']} {report['osVersion']}".strip(),
        f"Huella: {report['signature']}",
        "",
        report["stack"] or "(sin traza)",
    ]
    return "Error en la app", "\n".join(lines)


def process_report(
    raw_body: bytes,
    client_ip: str,
    *,
    limiter: submissions.RateLimiter,
    store: Optional[Callable[[Dict[str, str]], Optional[bool]]] = None,
    send: Optional[Callable[[str, str, Optional[str]], bool]] = None,
) -> Tuple[int, Dict[str, Any]]:
    store = store or store_in_mongo
    send = send or submissions.send_email_resend
    if len(raw_body) > MAX_BODY_BYTES:
        return 413, {"ok": False}
    if not limiter.allow(client_ip):
        return 429, {"ok": False}
    try:
        payload = json.loads(raw_body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return 400, {"ok": False}
    report = validate(payload)
    if report is None:
        return 422, {"ok": False}

    first_time = store(report)
    # Correo solo la primera vez que aparece ese error (o si no se pudo
    # guardar, para no perderlo).
    emailed = False
    if first_time is not False:
        subject, text = build_email(report)
        emailed = send(subject, text, None)
    print(f"[INFO] Informe de error {report['signature']} (nuevo={first_time}, correo={emailed}).")
    return 200, {"ok": True}
