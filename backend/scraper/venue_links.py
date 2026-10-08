"""Enlace «Más información» a la página propia de cada actividad.

Muchos lugares publican cada acto en su web. Aquí se abre la agenda de los
lugares apuntados en venue_agendas.json, se recogen los enlaces a sus actos y
se emparejan con nuestras actividades por el nombre. Con una coincidencia
clara se usa esa página; si no, la agenda del lugar. Nunca se inventa nada.

Cada entrada de venue_agendas.json:
    place    texto que debe aparecer en el nombre del lugar (sin tildes)
    agenda   página general del lugar, que se usa cuando no hay coincidencia
    pages    páginas donde buscar los actos (por defecto, la agenda)
    events   trozo de dirección que distingue la página de un acto
    hosts    otros dominios del mismo lugar (antiguos o genéricos)
    browser  true si la web solo se deja leer con un navegador de verdad
"""

from __future__ import annotations

import difflib
import html
import json
import os
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

CONFIG = Path(__file__).with_name("venue_agendas.json")
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)

# Palabras que no distinguen un acto de otro.
STOPWORDS = set(
    "a al con de del el en la las los para por un una y o e the and of in "
    "sala zaragoza zgz anos aniversario presenta presentan concierto conciertos "
    "exposicion taller espectaculo visita ciclo gira tour festival".split()
)

Link = Tuple[str, str]  # (dirección, texto del enlace)


def plain(text: Any) -> str:
    text = unicodedata.normalize("NFKD", str(text or "").lower())
    return "".join(c for c in text if not unicodedata.combining(c))


def tokens(text: Any, extra_stop: Iterable[str] = ()) -> List[str]:
    stop = STOPWORDS | set(extra_stop)
    seen: List[str] = []
    for word in re.findall(r"[a-z0-9]+", plain(text)):
        if word not in stop and (len(word) > 1 or word.isdigit()) and word not in seen:
            seen.append(word)
    return seen


def _same(a: str, b: str) -> bool:
    if a == b:
        return True
    # Erratas: «leyebdarian» y «leyendarian».
    return min(len(a), len(b)) >= 5 and difflib.SequenceMatcher(None, a, b).ratio() >= 0.84


def _score(title: List[str], candidate: List[str]) -> Tuple[float, float]:
    """Parecido entre dos nombres, de 0 a 1: (el mejor de los dos sentidos, el
    peor). Una palabra con errata vale la mitad. Hacen falta dos palabras en
    común y al menos una idéntica; si el título es de una sola palabra, esa
    palabra, idéntica y larga."""
    if not title or not candidate:
        return (0.0, 0.0)
    weight, exact, hits = 0.0, 0, 0
    for word in title:
        if word in candidate:
            weight, exact, hits = weight + 1, exact + 1, hits + 1
        elif any(_same(word, other) for other in candidate):
            weight, hits = weight + 0.5, hits + 1
    if len(title) == 1:
        enough = exact == 1 and len(title[0]) >= 6
    else:
        enough = hits >= 2 and exact >= 1
    if not enough:
        return (0.0, 0.0)
    forward, backward = weight / len(title), weight / len(candidate)
    return (max(forward, backward), min(forward, backward))


def best_link(title: str, links: List[Link], noise: Iterable[str] = ()) -> str:
    """La página del acto que mejor coincide con el título, o "" si ninguna
    coincide con claridad o hay dos candidatas igual de buenas."""
    wanted = tokens(title, noise)
    scored = []
    for url, text in links:
        slug = urlparse(url).path.rstrip("/").split("/")[-1]
        score = max(_score(wanted, tokens(slug, noise)), _score(wanted, tokens(text, noise)))
        if score[0] >= 0.6:
            scored.append((score, url))
    if not scored:
        return ""
    scored.sort(reverse=True)
    if len(scored) > 1:
        (best, _), (second, _) = scored[0], scored[1]
        if best[0] - second[0] < 0.15 and best[1] - second[1] < 0.15:
            return ""
    return scored[0][1]


def extract_links(page_html: str, page_url: str, pattern: str) -> List[Link]:
    """Enlaces de la página cuya dirección contiene `pattern`."""
    found: Dict[str, str] = {}
    for match in re.finditer(r'<a\b[^>]*?href=["\']([^"\'#]+)["\'][^>]*>(.*?)</a>', page_html, re.I | re.S):
        url = urljoin(page_url, html.unescape(match.group(1))).split("?")[0]
        if pattern not in urlparse(url).path or urlparse(url).scheme not in ("http", "https"):
            continue
        text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(match.group(2)))).strip()
        if len(text) > len(found.get(url, "")) or url not in found:
            found[url] = text
    return list(found.items())


def _host(url: str) -> str:
    return (urlparse(url).hostname or "").lower().removeprefix("www.")


def _is_council(url: str) -> bool:
    host = _host(url)
    return host == "zaragoza.es" or host.endswith(".zaragoza.es")


def venue_for(place: Any, config: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    name = plain(place)
    for entry in config:
        if plain(entry.get("place")) in name and entry.get("place"):
            return entry
    return None


def resolve(event: Dict[str, Any], entry: Dict[str, Any], links: List[Link]) -> str:
    """El enlace que debe llevar la actividad celebrada en ese lugar."""
    current = str(event.get("moreInfoUrl") or "")
    own_hosts = {_host(entry["agenda"])} | {h.lower().removeprefix("www.") for h in entry.get("hosts", [])}
    from_venue = _host(current) in own_hosts
    if current and not _is_council(current) and not from_venue:
        return current  # enlace propio de la actividad en otra web: se respeta
    noise = tokens(entry.get("place"))
    match = best_link(str(event.get("title") or ""), links, noise)
    if match:
        return match
    pattern = entry.get("events")
    if from_venue and pattern and pattern in urlparse(current).path:
        return current  # ya apuntaba a la página de un acto
    return entry["agenda"]


def load_config(path: Path = CONFIG) -> List[Dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    return [e for e in data if isinstance(e, dict) and e.get("place") and str(e.get("agenda", "")).startswith("http")]


def _download(url: str) -> str:
    request = Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": "es-ES,es;q=0.9"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


def _render(urls: List[str]) -> Dict[str, str]:
    """Abre las páginas con Chrome: algunas webs rechazan a los programas."""
    from playwright.sync_api import sync_playwright

    chrome = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    pages: Dict[str, str] = {}
    with sync_playwright() as playwright:
        args: Dict[str, Any] = {"headless": True}
        if os.name == "nt" and os.path.exists(chrome):
            args["executable_path"] = chrome
        browser = playwright.chromium.launch(**args)
        context = browser.new_context(locale="es-ES", user_agent=USER_AGENT)
        try:
            for url in urls:
                page = context.new_page()
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=45000)
                    page.wait_for_timeout(5000)
                    pages[url] = page.content()
                except Exception as exc:  # noqa: BLE001 - una web caída no para el resto
                    print(f"[WARN] No se pudo abrir {url}: {exc}", file=sys.stderr)
                finally:
                    page.close()
        finally:
            browser.close()
    return pages


def collect_links(
    entries: List[Dict[str, Any]],
    download: Callable[[str], str] = _download,
    render: Callable[[List[str]], Dict[str, str]] = _render,
) -> Dict[str, List[Link]]:
    """Enlaces a actos de cada lugar, por su `place`."""
    out: Dict[str, List[Link]] = {}
    pending = [e for e in entries if e.get("events")]
    rendered: Dict[str, str] = {}
    browser_urls = [u for e in pending if e.get("browser") for u in e.get("pages", [e["agenda"]])]
    if browser_urls:
        try:
            rendered = render(browser_urls)
        except Exception as exc:  # noqa: BLE001
            print(f"[WARN] Navegador no disponible para las agendas: {exc}", file=sys.stderr)
    for entry in pending:
        links: Dict[str, str] = {}
        for url in entry.get("pages", [entry["agenda"]]):
            try:
                page_html = rendered[url] if entry.get("browser") else download(url)
            except Exception as exc:  # noqa: BLE001
                print(f"[WARN] Agenda de «{entry['place']}» no disponible ({url}): {exc}", file=sys.stderr)
                continue
            links.update(dict(extract_links(page_html, url, entry["events"])))
        out[entry["place"]] = list(links.items())
    return out


def apply(events: List[Dict[str, Any]], config: Optional[List[Dict[str, Any]]] = None, links=None) -> int:
    """Cambia en su sitio el enlace de las actividades de los lugares
    apuntados. Devuelve cuántas llevan ahora a la página de su acto."""
    config = load_config() if config is None else config
    used = [e for e in config if any(venue_for(ev.get("place"), [e]) for ev in events)]
    if not used:
        return 0
    links = collect_links(used) if links is None else links
    exact = 0
    for event in events:
        entry = venue_for(event.get("place"), used)
        if not entry:
            continue
        found = links.get(entry["place"], [])
        url = resolve(event, entry, found)
        exact += url in {u for u, _ in found}
        event["moreInfoUrl"] = url
    return exact
