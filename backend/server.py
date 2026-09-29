#!/usr/bin/env python3
"""Servidor mínimo para exponer la agenda cultural en JSON.

Flujo:
1. Se conecta a MongoDB Atlas usando la variable de entorno MONGODB_URI.
2. Sirve los eventos de la colección 'events' en /events.
3. Expone una pequeña home para pruebas locales.
"""

from __future__ import annotations

import gzip
import json
import os
import sys
import time
from datetime import date, timedelta
from urllib.parse import parse_qs, urlparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from pymongo import MongoClient

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


class EventHandler(BaseHTTPRequestHandler):
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
