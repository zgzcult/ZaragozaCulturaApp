#!/usr/bin/env python3
"""Servidor mínimo para exponer la agenda cultural en JSON.

Flujo:
1. asegura que exista backend/data/zaragoza_events.json
2. si no existe, lo genera ejecutando el scraper
3. sirve ese JSON en /events
4. expone una pequeña home para pruebas locales
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
SCRAPER_PATH = BASE_DIR / "scraper" / "scraper.py"
DATA_PATH = BASE_DIR / "data" / "zaragoza_events.json"
SAMPLE_PATH = BASE_DIR / "data" / "zaragoza_events.sample.json"


def ensure_events_file() -> Path:
    if DATA_PATH.exists() and DATA_PATH.stat().st_size > 0:
        return DATA_PATH

    # Intentamos primero ejecutar el scraper para obtener datos reales
    command = [
        sys.executable,
        str(SCRAPER_PATH),
        "--base-url",
        "https://www.zaragoza.es/sede/servicio/cultura/",
        "--output",
        str(DATA_PATH),
        "--limit",
        "10000",
    ]
    subprocess.run(command, check=False)
    if DATA_PATH.exists() and DATA_PATH.stat().st_size > 0:
        return DATA_PATH

    # Si el scraper falla, usamos los datos de ejemplo como último recurso
    if SAMPLE_PATH.exists():
        DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
        DATA_PATH.write_text(SAMPLE_PATH.read_text(encoding="utf-8"), encoding="utf-8")
        return DATA_PATH

    raise FileNotFoundError("No se pudo generar el JSON de eventos ni encontrar datos de ejemplo.")


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
                json_path = ensure_events_file()
                payload = json_path.read_text(encoding="utf-8")
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
