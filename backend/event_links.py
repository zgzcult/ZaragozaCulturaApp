"""Página de enlace de una actividad: lo que se abre al pulsar el enlace que
la app pone al compartir.

Muestra la actividad y un botón que la abre dentro de la app (esquema propio
`manazaragoza://`). Lleva las etiquetas Open Graph para que WhatsApp y otras
apps enseñen una vista previa con el título y la foto.
"""

from __future__ import annotations

import html
import os
import re
from typing import Any, Dict, Optional

APP_SCHEME = "manazaragoza"
_ID_RE = re.compile(r"^[0-9a-f]{8,64}$")
_MONTHS = [
    "enero", "febrero", "marzo", "abril", "mayo", "junio",
    "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
]


def valid_event_id(event_id: str) -> bool:
    return bool(_ID_RE.match(event_id or ""))


def app_link(event_id: str) -> str:
    """Enlace que abre la actividad dentro de la app."""
    return f"{APP_SCHEME}://open/evento/{event_id}"


def find_event(event_id: str) -> Optional[Dict[str, Any]]:
    """La actividad en MongoDB, o None si no existe o no hay conexión."""
    uri = os.environ.get("MONGODB_URI")
    if not uri or not valid_event_id(event_id):
        return None
    try:
        from pymongo import MongoClient

        client = MongoClient(uri, serverSelectionTimeoutMS=5000)
        fields = {"_id": 0, "title": 1, "date": 1, "time": 1, "place": 1, "description": 1, "imageUrl": 1}
        event = client["zaragoza_cultura"]["events"].find_one({"id": event_id}, fields)
        client.close()
        return event
    except Exception as exc:  # la página debe salir igualmente
        print(f"[WARN] No se pudo leer la actividad {event_id}: {exc}")
        return None


def _long_date(iso: str) -> str:
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})", iso or "")
    if not m or not 1 <= int(m.group(2)) <= 12:
        return ""
    return f"{int(m.group(3))} de {_MONTHS[int(m.group(2)) - 1]} de {m.group(1)}"


def _image_url(value: Any) -> str:
    url = value if isinstance(value, str) else ""
    if url.startswith("//"):
        url = "https:" + url
    elif url.startswith("/"):
        url = "https://www.zaragoza.es" + url
    return url if url.startswith("https://") else ""


PAGE = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Maña Zaragoza</title>
<meta property="og:title" content="{title}">
<meta property="og:description" content="{summary}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Maña Zaragoza">
{og_image}<style>
  body {{ font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color: #0b2d4a; background: #f7f6ef; margin: 0; }}
  main {{ max-width: 520px; margin: 0 auto; padding: 28px 22px 48px; line-height: 1.5; }}
  .brand {{ font-size: .8rem; letter-spacing: .12em; text-transform: uppercase; color: #ff6b4a; font-weight: 700; }}
  h1 {{ font-size: 1.6rem; line-height: 1.2; margin: .4rem 0 .8rem; }}
  .meta {{ color: #5b6b80; margin: .2rem 0; }}
  .btn {{ display: block; text-align: center; background: #0b2d4a; color: #fff; text-decoration: none; font-weight: 700; padding: 15px; border-radius: 16px; margin-top: 26px; }}
  .note {{ color: #5b6b80; font-size: .9rem; margin-top: 14px; text-align: center; }}
  .note a {{ color: #0b2d4a; }}
</style>
</head>
<body>
<main>
<div class="brand">Maña Zaragoza</div>
<h1>{title}</h1>
{meta}
<a class="btn" href="{link}">Abrir en la app</a>
<p class="note">{store}</p>
</main>
</body>
</html>
"""


def render_event_page(event_id: str, event: Optional[Dict[str, Any]], store_url: str = "") -> str:
    """HTML de la página de enlace. Si la actividad ya no existe (pasó o se
    retiró), se muestra una página genérica con el mismo botón."""
    esc = html.escape
    title = (event or {}).get("title") or "Actividad en Zaragoza"
    lines = []
    if event:
        when = " · ".join(p for p in (_long_date(str(event.get("date", ""))), str(event.get("time") or "")) if p)
        if when:
            lines.append(when)
        if event.get("place"):
            lines.append(str(event["place"]))
    else:
        lines.append("Esta actividad ya no está en la agenda. Abre la app para ver las de hoy.")
    summary = " · ".join(lines) or "Agenda cultural de Zaragoza"
    image = _image_url((event or {}).get("imageUrl"))
    store = (
        f'¿No tienes la app? <a href="{esc(store_url, quote=True)}">Descárgala gratis</a>.'
        if store_url.startswith("https://")
        else "¿No tienes la app? Muy pronto disponible."
    )
    return PAGE.format(
        title=esc(str(title)),
        summary=esc(summary, quote=True),
        og_image=f'<meta property="og:image" content="{esc(image, quote=True)}">\n' if image else "",
        meta="\n".join(f'<p class="meta">{esc(line)}</p>' for line in lines),
        link=esc(app_link(event_id) if valid_event_id(event_id) else f"{APP_SCHEME}://open/inicio", quote=True),
        store=store,
    )
