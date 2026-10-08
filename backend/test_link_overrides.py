"""Pruebas de las correcciones de enlaces. Ejecutar con:

    python backend/test_link_overrides.py
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import link_overrides as lo  # noqa: E402

FICHA = "https://www.zaragoza.es/sede/servicio/cultura/evento/7"


def event(code="7", url="https://teatro.example.org/", **extra):
    return {"id": "x" + code, "sourceId": code, "moreInfoUrl": url, "officialUrl": FICHA, **extra}


def rules(**changes):
    base = {"links": {}, "no_link": set(), "blocked_hosts": set(), "hidden": set(), "pending": set()}
    return {**base, **changes}


class ApplyTests(unittest.TestCase):
    def one(self, ev, **changes):
        return lo.apply([ev], rules(**changes))

    def test_sin_correcciones_se_queda_igual(self):
        out = self.one(event())[0]
        self.assertEqual(out["moreInfoUrl"], "https://teatro.example.org/")
        self.assertFalse(out["hideLink"])

    def test_enlace_fijo(self):
        out = self.one(event(), links={"7": "https://teatro.example.org/la-obra/"})[0]
        self.assertEqual(out["moreInfoUrl"], "https://teatro.example.org/la-obra/")
        self.assertFalse(out["hideLink"])

    def test_actividad_sin_enlace(self):
        out = self.one(event(), no_link={"7"})[0]
        self.assertEqual(out["moreInfoUrl"], "")
        self.assertTrue(out["hideLink"])

    def test_web_prohibida_deja_sin_enlace(self):
        for url in (FICHA, "https://zaragoza.es/x", "http://www.lasarmas.es"):
            out = self.one(event(url=url), blocked_hosts={"zaragoza.es", "lasarmas.es"})[0]
            self.assertTrue(out["hideLink"], url)
            self.assertEqual(out["moreInfoUrl"], "")

    def test_un_subdominio_distinto_no_esta_prohibido(self):
        url = "https://museos-cultura.zaragoza.es/info-visita/"
        out = self.one(event(url=url), blocked_hosts={"zaragoza.es"})[0]
        self.assertEqual(out["moreInfoUrl"], url)
        self.assertFalse(out["hideLink"])

    def test_sin_enlace_propio_cuenta_la_ficha(self):
        out = self.one(event(url=""), blocked_hosts={"zaragoza.es"})[0]
        self.assertTrue(out["hideLink"])
        self.assertEqual(self.one(event(url=""))[0]["moreInfoUrl"], FICHA)

    def test_el_enlace_fijo_tambien_respeta_las_webs_prohibidas(self):
        out = self.one(event(), links={"7": FICHA}, blocked_hosts={"zaragoza.es"})[0]
        self.assertTrue(out["hideLink"])

    def test_actividad_oculta(self):
        out = lo.apply([event("7"), event("8")], rules(hidden={"7"}))
        self.assertEqual([e["sourceId"] for e in out], ["8"])

    def test_no_modifica_la_actividad_original(self):
        source = event()
        self.one(source, no_link={"7"})
        self.assertEqual(source["moreInfoUrl"], "https://teatro.example.org/")
        self.assertNotIn("hideLink", source)


class LoadTests(unittest.TestCase):
    def test_fichero_ausente_o_roto(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "no.json"
            self.assertEqual(lo.load(path), rules())
            path.write_text("[1, 2", encoding="utf-8")
            self.assertEqual(lo.load(path), rules())

    def test_normaliza_y_descarta_lo_que_no_vale(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "r.json"
            path.write_text(
                '{"links": {"7": "https://a.org/x", "8": "sin protocolo"}, "blocked_hosts": ["WWW.Zaragoza.es"], "hidden": [9]}',
                encoding="utf-8",
            )
            data = lo.load(path)
            self.assertEqual(data["links"], {"7": "https://a.org/x"})
            self.assertEqual(data["blocked_hosts"], {"zaragoza.es"})
            self.assertEqual(data["hidden"], {"9"})

    def test_el_fichero_del_repositorio_es_valido(self):
        data = lo.load()
        self.assertIn("zaragoza.es", data["blocked_hosts"])
        for code, url in data["links"].items():
            self.assertTrue(code.isdigit(), code)
            self.assertTrue(url.startswith("https://"), url)
            self.assertNotIn(lo.host_of(url), data["blocked_hosts"], url)


if __name__ == "__main__":
    unittest.main()
