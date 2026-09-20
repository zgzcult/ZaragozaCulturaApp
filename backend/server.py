#!/usr/bin/env python3
"""Servidor mínimo para exponer la agenda cultural en JSON.

Flujo:
1. Se conecta a MongoDB Atlas usando la variable de entorno MONGODB_URI.
2. Sirve los eventos de la colección 'events' en /events.
3. Expone una pequeña home para pruebas locales.
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from pymongo import MongoClient

# Configuración de MongoDB
MONGODB_URI = os.environ.get("MONGODB_URI")

def get_events_from_db():
    if not MONGODB_URI:
        raise RuntimeError("MONGODB_URI no está configurada en las variables de entorno")

    try:
        client = MongoClient(MONGODB_URI, serverSelectionTimeoutMS=5000)
        db = client["zaragoza_cultura"]
        collection = db["events"]
        # Retornamos los eventos excluyendo el _id interno de MongoDB
        events = list(collection.find({}, {"_id": 0}))
        client.close()
        return events
    except Exception as exc:
        raise RuntimeError(f"Error conectando a MongoDB: {exc}")

class EventHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(
                b"Agenda Zaragoza Cultura backend. Use /events to fetch the JSON payload."
            )
            return

        if self.path in ("/events", "/events.json"):
            try:
                events = get_events_from_db()
                payload = json.dumps(events, ensure_ascii=False, indent=2)
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(payload.encode("utf-8"))
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
