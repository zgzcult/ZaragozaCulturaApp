#!/usr/bin/env python3
"""Mantenimiento de rewrites.json (las descripciones propias).

    python backend/rewrites_tool.py pending DIR   deja en DIR, en lotes, los
                                                 textos que faltan por reescribir
    python backend/rewrites_tool.py merge FILE…  añade {huella: texto} al fichero
    python backend/rewrites_tool.py apply DIR     añade los hecho_*.json de DIR, pero
                                                 solo lo que estaba pendiente allí
    python backend/rewrites_tool.py prune        quita las huellas que ya no se usan

`pending` y `prune` preguntan al servidor (/rewrites/pending). Con --bootstrap,
`pending` parte de /events?all: solo sirve antes del primer despliegue,
mientras /events aún devuelve el texto original.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rewrites  # noqa: E402

SERVER = "https://zaragoza-cultura-app.onrender.com"
BATCH = 20


def _get(path: str):
    request = urllib.request.Request(SERVER + path, headers={"User-Agent": "rewrites-tool"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8"))


def _save(data: dict) -> None:
    text = json.dumps(dict(sorted(data.items())), ensure_ascii=False, indent=0)
    rewrites.PATH.write_text(text + "\n", encoding="utf-8", newline="\n")


def cmd_pending(args: list) -> int:
    bootstrap = "--bootstrap" in args
    target = Path([a for a in args if not a.startswith("--")][0])
    if bootstrap:
        items = rewrites.pending(_get("/events?all=1"), rewrites.load())
    else:
        items = _get("/rewrites/pending")["pending"]
    target.mkdir(parents=True, exist_ok=True)
    for old in target.glob("pendientes_*.json"):
        old.unlink()
    for start in range(0, len(items), BATCH):
        name = target / f"pendientes_{start // BATCH + 1:02d}.json"
        name.write_text(
            json.dumps(items[start : start + BATCH], ensure_ascii=False, indent=1),
            encoding="utf-8",
        )
    print(f"{len(items)} textos pendientes en {-(-len(items) // BATCH)} lotes")
    return 0


def cmd_merge(files: list) -> int:
    data = rewrites.load()
    added = 0
    for name in files:
        for key, text in json.loads(Path(name).read_text(encoding="utf-8")).items():
            text = " ".join(text.split()) if isinstance(text, str) else ""
            if len(key) != 16 or not text:
                print(f"[ERROR] entrada no válida en {name}: {key!r}", file=sys.stderr)
                return 1
            added += key not in data
            data[key] = text
    _save(data)
    print(f"{added} textos nuevos; {len(data)} en total")
    return 0


def acceptable(original: str, text: str) -> bool:
    """Una reescritura razonable: con contenido, distinta del original y sin
    alargarlo (los textos largos se condensan, no crecen)."""
    text = " ".join(text.split()) if isinstance(text, str) else ""
    original = " ".join(original.split())
    return bool(text) and text != original and len(text) <= max(400, int(len(original) * 1.3))


def cmd_apply(args: list) -> int:
    """Para la ejecución automática: no se fía de lo que haya en DIR más que
    para las huellas que estaban pendientes."""
    folder = Path(args[0])
    wanted = {}
    for name in sorted(folder.glob("pendientes_*.json")):
        for item in json.loads(name.read_text(encoding="utf-8")):
            wanted[item["key"]] = item["description"]
    data = rewrites.load()
    added, rejected = 0, []
    for name in sorted(folder.glob("hecho_*.json")):
        try:
            done = json.loads(name.read_text(encoding="utf-8-sig"))
        except ValueError as exc:
            print(f"[WARN] {name.name} no es JSON válido: {exc}", file=sys.stderr)
            continue
        if not isinstance(done, dict):
            continue
        for key, text in done.items():
            if key not in wanted or not acceptable(wanted[key], text):
                rejected.append(key)
                continue
            added += key not in data
            data[key] = " ".join(text.split())
    if added:
        _save(data)
    missing = len([k for k in wanted if k not in data])
    print(f"{added} textos nuevos; {len(rejected)} rechazados; {missing} siguen pendientes")
    return 0


def cmd_prune(_args: list) -> int:
    live = set(_get("/rewrites/pending")["live"])
    data = rewrites.load()
    kept = {k: v for k, v in data.items() if k in live}
    _save(kept)
    print(f"{len(data) - len(kept)} textos retirados; quedan {len(kept)}")
    return 0


if __name__ == "__main__":
    commands = {"pending": cmd_pending, "merge": cmd_merge, "apply": cmd_apply, "prune": cmd_prune}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print(__doc__)
        sys.exit(2)
    sys.exit(commands[sys.argv[1]](sys.argv[2:]))
