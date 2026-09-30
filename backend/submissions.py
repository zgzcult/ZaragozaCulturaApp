"""Recepción de sugerencias y eventos que envían los usuarios desde la app.

Cada envío se valida, se guarda en MongoDB (colección `submissions`, así no se
pierde aunque falle el correo) y se avisa por correo con un servicio de envío
por HTTP (Resend). Render bloquea SMTP en el plan gratuito, por eso no se usa
Gmail directamente.

Variables de entorno (se definen en Render, nunca en el repositorio):
    RESEND_API_KEY   clave de Resend
    NOTIFY_EMAIL     dirección que recibe los avisos
    EMAIL_FROM       remitente (opcional; por defecto el de pruebas de Resend)
    MONGODB_URI      conexión a MongoDB (ya existente)
"""

from __future__ import annotations

import json
import os
import re
import ssl
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional, Tuple

# tipo -> asunto del correo
SUBJECTS = {"mejora": "Mejora", "evento": "Evento"}

MAX_TITLE = 120
MAX_DESCRIPTION = 2000
MAX_CONTACT = 200
MAX_BODY_BYTES = 16_000

RATE_LIMIT = 5  # envíos por IP...
RATE_WINDOW = 3600  # ...cada hora

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class RateLimiter:
    """Limita cuántos envíos puede hacer una misma IP por hora (en memoria)."""

    def __init__(self, limit: int = RATE_LIMIT, window: int = RATE_WINDOW) -> None:
        self.limit = limit
        self.window = window
        self._hits: Dict[str, List[float]] = {}
        self._lock = threading.Lock()

    def allow(self, key: str, now: Optional[float] = None) -> bool:
        now = time.time() if now is None else now
        with self._lock:
            recent = [t for t in self._hits.get(key, []) if now - t < self.window]
            if len(recent) >= self.limit:
                self._hits[key] = recent
                return False
            recent.append(now)
            self._hits[key] = recent
            return True


def _clean(value: Any, limit: int) -> str:
    text = value if isinstance(value, str) else ""
    # Sin caracteres de control (salvo saltos de línea y tabuladores).
    text = "".join(ch for ch in text if ch in "\n\t" or ord(ch) >= 32)
    return text.strip()[:limit]


def validate(payload: Any) -> Tuple[Optional[Dict[str, str]], Optional[str]]:
    """Devuelve (datos limpios, None) o (None, mensaje de error)."""
    if not isinstance(payload, dict):
        return None, "Datos no válidos."
    kind = _clean(payload.get("type"), 20)
    if kind not in SUBJECTS:
        return None, "Tipo de envío no válido."
    title = _clean(payload.get("title"), MAX_TITLE)
    description = _clean(payload.get("description"), MAX_DESCRIPTION)
    contact = _clean(payload.get("contact"), MAX_CONTACT)
    if len(title) < 3:
        return None, "El título es demasiado corto."
    if len(description) < 10:
        return None, "La descripción es demasiado corta."
    return {"type": kind, "title": title, "description": description, "contact": contact}, None


def build_email(clean: Dict[str, str]) -> Tuple[str, str]:
    """Asunto y texto del correo."""
    subject = SUBJECTS[clean["type"]]
    lines = [f"Título: {clean['title']}", "", clean["description"]]
    if clean["contact"]:
        lines += ["", f"Contacto: {clean['contact']}"]
    return subject, "\n".join(lines)


def _ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def send_email_resend(subject: str, text: str, reply_to: Optional[str] = None) -> bool:
    """Envía el aviso por Resend. Devuelve False si no está configurado o falla."""
    api_key = os.environ.get("RESEND_API_KEY", "").strip()
    to = os.environ.get("NOTIFY_EMAIL", "").strip()
    if not api_key or not to:
        return False
    body: Dict[str, Any] = {
        "from": os.environ.get("EMAIL_FROM", "Zaragoza Cultura <onboarding@resend.dev>"),
        "to": [to],
        "subject": subject,
        "text": text,
    }
    if reply_to:
        body["reply_to"] = reply_to
    request = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "zaragoza-cultura-app/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20, context=_ssl_context()) as response:
            return 200 <= response.status < 300
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"[WARN] No se pudo enviar el correo: {exc}")
        return False


def store_in_mongo(doc: Dict[str, Any]) -> bool:
    """Guarda el envío en MongoDB. Devuelve False si no se pudo."""
    uri = os.environ.get("MONGODB_URI")
    if not uri:
        return False
    try:
        from pymongo import MongoClient

        client = MongoClient(uri, serverSelectionTimeoutMS=5000)
        client["zaragoza_cultura"]["submissions"].insert_one(doc)
        client.close()
        return True
    except Exception as exc:  # no debe tumbar el servidor
        print(f"[WARN] No se pudo guardar el envío: {exc}")
        return False


def process_submission(
    raw_body: bytes,
    client_ip: str,
    *,
    limiter: RateLimiter,
    store: Optional[Callable[[Dict[str, Any]], bool]] = None,
    send: Optional[Callable[[str, str, Optional[str]], bool]] = None,
) -> Tuple[int, Dict[str, Any]]:
    """Procesa un envío. Devuelve (código HTTP, respuesta JSON)."""
    store = store or store_in_mongo
    send = send or send_email_resend
    if len(raw_body) > MAX_BODY_BYTES:
        return 413, {"ok": False, "error": "El mensaje es demasiado largo."}
    if not limiter.allow(client_ip):
        return 429, {"ok": False, "error": "Has enviado demasiados mensajes. Inténtalo más tarde."}
    try:
        payload = json.loads(raw_body.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        return 400, {"ok": False, "error": "Datos no válidos."}

    clean, error = validate(payload)
    if clean is None:
        return 422, {"ok": False, "error": error}

    doc = dict(clean)
    doc["createdAt"] = datetime.now(timezone.utc).isoformat()
    stored = store(doc)

    subject, text = build_email(clean)
    reply_to = clean["contact"] if _EMAIL_RE.match(clean["contact"]) else None
    emailed = send(subject, text, reply_to)

    if not stored and not emailed:
        return 503, {"ok": False, "error": "No se pudo registrar el mensaje. Inténtalo más tarde."}
    return 200, {"ok": True}
