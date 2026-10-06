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

import base64
import binascii
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
MAX_BODY_BYTES = 16_000  # texto del envío (sin la foto)

# Foto opcional de «Envía tu evento»: la app la reduce antes de enviarla.
MAX_PHOTO_BYTES = 1_500_000
# El envío completo: el texto más la foto en base64 (ocupa un tercio más).
MAX_BODY_WITH_PHOTO = MAX_BODY_BYTES + MAX_PHOTO_BYTES * 4 // 3 + 1_000

_PHOTO_TYPES = (
    (b"\xff\xd8\xff", "jpg"),
    (b"\x89PNG\r\n\x1a\n", "png"),
)

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


def decode_photo(payload: Any) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Foto adjunta al envío: (None, None) si no hay; ({"bytes", "ext"}, None)
    si es válida; (None, error) si no lo es. Solo se admiten JPG y PNG, y se
    comprueba el contenido real del archivo, no su nombre."""
    photo = payload.get("photo") if isinstance(payload, dict) else None
    if photo in (None, "", {}):
        return None, None
    data = photo.get("data") if isinstance(photo, dict) else None
    if not isinstance(data, str) or not data:
        return None, "La foto no es válida."
    if len(data) > MAX_PHOTO_BYTES * 4 // 3 + 4:
        return None, "La foto es demasiado grande."
    try:
        raw = base64.b64decode(data, validate=True)
    except (binascii.Error, ValueError):
        return None, "La foto no es válida."
    if len(raw) > MAX_PHOTO_BYTES:
        return None, "La foto es demasiado grande."
    for magic, ext in _PHOTO_TYPES:
        if raw.startswith(magic):
            return {"bytes": raw, "ext": ext}, None
    return None, "La foto debe ser una imagen JPG o PNG."


def build_email(clean: Dict[str, str], has_photo: bool = False) -> Tuple[str, str]:
    """Asunto y texto del correo."""
    subject = SUBJECTS[clean["type"]]
    lines = [f"Título: {clean['title']}", "", clean["description"]]
    if clean["contact"]:
        lines += ["", f"Contacto: {clean['contact']}"]
    if has_photo:
        lines += ["", "Foto: adjunta a este correo."]
    return subject, "\n".join(lines)


def _ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def send_email_resend(
    subject: str,
    text: str,
    reply_to: Optional[str] = None,
    attachments: Optional[List[Dict[str, str]]] = None,
) -> bool:
    """Envía el aviso por Resend. Devuelve False si no está configurado o falla."""
    api_key = os.environ.get("RESEND_API_KEY", "").strip()
    to = os.environ.get("NOTIFY_EMAIL", "").strip()
    if not api_key or not to:
        missing = [n for n, v in (("RESEND_API_KEY", api_key), ("NOTIFY_EMAIL", to)) if not v]
        print(f"[WARN] Correo no enviado: falta la variable de entorno {', '.join(missing)}.")
        return False
    body: Dict[str, Any] = {
        "from": os.environ.get("EMAIL_FROM", "Maña Zaragoza <onboarding@resend.dev>"),
        "to": [to],
        "subject": subject,
        "text": text,
    }
    if reply_to:
        body["reply_to"] = reply_to
    if attachments:
        # [{"filename": "evento.jpg", "content": "<base64>"}]
        body["attachments"] = attachments
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
            ok = 200 <= response.status < 300
            if not ok:
                print(f"[WARN] Resend respondió {response.status}.")
            return ok
    except urllib.error.HTTPError as exc:
        # Resend explica el motivo en el cuerpo de la respuesta (clave no
        # válida, destinatario no permitido con el remitente de pruebas...).
        detail = exc.read().decode("utf-8", "replace")[:300]
        print(f"[WARN] Resend rechazó el correo (HTTP {exc.code}): {detail}")
        return False
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"[WARN] No se pudo contactar con Resend: {exc}")
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
    send: Optional[Callable[..., bool]] = None,
) -> Tuple[int, Dict[str, Any]]:
    """Procesa un envío. Devuelve (código HTTP, respuesta JSON)."""
    store = store or store_in_mongo
    send = send or send_email_resend
    # Solo un envío con foto puede pasar del límite del texto.
    too_long = len(raw_body) > MAX_BODY_WITH_PHOTO or (
        len(raw_body) > MAX_BODY_BYTES and b'"photo"' not in raw_body
    )
    if too_long:
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

    photo, error = decode_photo(payload)
    if error:
        return 422, {"ok": False, "error": error}
    if photo and clean["type"] != "evento":
        return 422, {"ok": False, "error": "Este envío no admite fotos."}
    # Sin contar la foto, el texto sigue teniendo su límite de siempre.
    photo_chars = len(payload["photo"]["data"]) if photo else 0
    if len(raw_body) - photo_chars > MAX_BODY_BYTES:
        return 413, {"ok": False, "error": "El mensaje es demasiado largo."}

    # La foto no se guarda en la base de datos: solo viaja en el correo.
    doc = dict(clean)
    doc["createdAt"] = datetime.now(timezone.utc).isoformat()
    doc["hasPhoto"] = photo is not None
    stored = store(doc)

    subject, text = build_email(clean, has_photo=photo is not None)
    reply_to = clean["contact"] if _EMAIL_RE.match(clean["contact"]) else None
    if photo:
        attachment = {
            "filename": f"evento.{photo['ext']}",
            "content": base64.b64encode(photo["bytes"]).decode("ascii"),
        }
        emailed = send(subject, text, reply_to, [attachment])
    else:
        emailed = send(subject, text, reply_to)
    print(f"[INFO] Envío '{clean['type']}' recibido (guardado={stored}, correo={emailed}).")

    if not stored and not emailed:
        return 503, {"ok": False, "error": "No se pudo registrar el mensaje. Inténtalo más tarde."}
    return 200, {"ok": True}
