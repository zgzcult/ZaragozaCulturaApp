#!/usr/bin/env python3
"""Servidor mínimo para exponer la agenda cultural en JSON.

Flujo:
1. Se conecta a MongoDB Atlas usando la variable de entorno MONGODB_URI.
2. Sirve los eventos de la colección 'events' en /events.
3. Expone una pequeña home para pruebas locales.
"""

from __future__ import annotations

import gzip
import html
import json
import os
import sys
import time
from datetime import date, timedelta
from urllib.parse import parse_qs, urlparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from pymongo import MongoClient

import submissions

# Configuración de MongoDB
MONGODB_URI = os.environ.get("MONGODB_URI")

DEFAULT_DAYS = 50  # la app muestra 45 días; margen extra
CACHE_SECONDS = 300
_cache = {}


def get_events_from_db(days=None):
    """Eventos de hoy (-1 día) a hoy+days. days=None devuelve todos."""
    if not MONGODB_URI:
        raise RuntimeError("MONGODB_URI no está configurada en las variables de entorno")

    query = {}
    if days is not None:
        start = date.today() - timedelta(days=1)
        end = date.today() + timedelta(days=days)
        query = {"date": {"$gte": start.isoformat(), "$lte": end.isoformat()}}

    try:
        client = MongoClient(MONGODB_URI, serverSelectionTimeoutMS=5000)
        events = list(client["zaragoza_cultura"]["events"].find(query, {"_id": 0}))
        client.close()
        return events
    except Exception as exc:
        raise RuntimeError(f"Error conectando a MongoDB: {exc}")


def get_payload(days):
    """JSON compacto en bytes, con caché en memoria."""
    hit = _cache.get(days)
    if hit and time.time() - hit[0] < CACHE_SECONDS:
        return hit[1]
    events = get_events_from_db(days)
    payload = json.dumps(events, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    _cache[days] = (time.time(), payload)
    return payload


APP_LANDING_PAGE = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Zaragoza Cultura · La agenda cultural de Zaragoza</title>
<meta property="og:title" content="Zaragoza Cultura">
<meta property="og:description" content="Todas las actividades culturales de Zaragoza en una app: música, teatro, exposiciones y más.">
<meta property="og:type" content="website">
<style>
  body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color: #10243e; background: #f8fafd; margin: 0; display: flex; min-height: 100vh; align-items: center; justify-content: center; }
  main { max-width: 480px; padding: 32px 24px; text-align: center; line-height: 1.5; }
  h1 { margin-bottom: .3rem; }
  p { color: #425b71; }
</style>
</head>
<body>
<main>
<h1>Zaragoza Cultura</h1>
<p>Todas las actividades culturales de Zaragoza en una app: música, teatro, exposiciones y mucho más.</p>
<p><strong>Muy pronto disponible.</strong></p>
</main>
</body>
</html>
"""

PRIVACY_TEMPLATE = Path(__file__).with_name("privacy.html")
PRIVACY_DATE = "29 de septiembre de 2026"


def render_privacy_page() -> str:
    """Política de privacidad. Los datos del responsable se leen del entorno
    (PRIVACY_CONTROLLER y PRIVACY_CONTACT en Render) para no guardarlos en el
    repositorio."""
    pending = "[pendiente de completar]"
    values = {
        "{{RESPONSABLE}}": os.environ.get("PRIVACY_CONTROLLER", pending),
        "{{CONTACTO}}": os.environ.get("PRIVACY_CONTACT", pending),
        "{{FECHA}}": PRIVACY_DATE,
    }
    page = PRIVACY_TEMPLATE.read_text(encoding="utf-8")
    for marker, value in values.items():
        page = page.replace(marker, html.escape(value))
    return page


_submission_limiter = submissions.RateLimiter()


class EventHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        # Se lee siempre el mensaje (si no es enorme): cerrar la conexión con
        # datos sin leer puede hacer que el cliente reciba un reset en vez de
        # la respuesta.
        raw = self.rfile.read(length) if 0 < length <= submissions.MAX_BODY_BYTES else b""

        if urlparse(self.path).path != "/submit":
            status, body = 404, {"error": "Not found"}
        elif length > submissions.MAX_BODY_BYTES:
            status, body = 413, {"ok": False, "error": "El mensaje es demasiado largo."}
        else:
            # Render pasa la IP real en X-Forwarded-For.
            forwarded = self.headers.get("X-Forwarded-For", "")
            ip = forwarded.split(",")[0].strip() or self.client_address[0]
            status, body = submissions.process_submission(raw, ip, limiter=_submission_limiter)

        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if urlparse(self.path).path in ("/", "/index", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(
                b"Agenda Zaragoza Cultura backend. Use /events to fetch the JSON payload."
            )
            return

        url = urlparse(self.path)
        if url.path == "/app":
            # Enlace estable para compartir la app. Cuando esté publicada, basta
            # con definir APP_STORE_URL en Render para redirigir a la tienda.
            store_url = os.environ.get("APP_STORE_URL", "").strip()
            if store_url.startswith("https://"):
                self.send_response(302)
                self.send_header("Location", store_url)
                self.end_headers()
                return
            page = APP_LANDING_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page)))
            self.end_headers()
            self.wfile.write(page)
            return

        if url.path in ("/privacidad", "/privacy"):
            page = render_privacy_page().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(page)))
            self.end_headers()
            self.wfile.write(page)
            return

        if url.path in ("/events", "/events.json"):
            try:
                params = parse_qs(url.query)
                if "all" in params:
                    days = None
                else:
                    try:
                        days = max(1, min(int(params.get("days", [DEFAULT_DAYS])[0]), 400))
                    except ValueError:
                        days = DEFAULT_DAYS
                payload = get_payload(days)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                if "gzip" in self.headers.get("Accept-Encoding", ""):
                    payload = gzip.compress(payload, compresslevel=6)
                    self.send_header("Content-Encoding", "gzip")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            except Exception as exc:
                self.send_response(500)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(exc)}).encode("utf-8"))
                return

        self.send_response(404)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps({"error": "Not found"}).encode("utf-8"))

    def log_message(self, format, *args):
        return

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    server = ThreadingHTTPServer(("0.0.0.0", port), EventHandler)
    print(f"[OK] Servidor de eventos activos en http://localhost:{port}/events")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[STOP] Servidor detenido.")
    finally:
        server.server_close()
