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
    base = {
        "links": {},
        "no_link": set(),
        "allowed_hosts": {"teatro.example.org", "auditoriozaragoza.com", "museos-cultura.zaragoza.es", "a.org"},
        "blocked_hosts": set(),
        "home_only": {},
        "hidden": set(),
        "pending": set(),
    }
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
        self.assertEqual(self.one(event(url=""), allowed_hosts={"zaragoza.es"})[0]["moreInfoUrl"], FICHA)

    def test_el_enlace_fijo_tambien_respeta_las_webs_prohibidas(self):
        out = self.one(event(), links={"7": FICHA}, blocked_hosts={"zaragoza.es"})[0]
        self.assertTrue(out["hideLink"])

    def test_web_que_solo_admite_enlaces_a_su_portada(self):
        home = {"auditoriozaragoza.com": "https://auditoriozaragoza.com/"}
        for url in (
            "https://auditoriozaragoza.com/programacion/el-lago-de-los-cisnes-10/",
            "http://www.auditoriozaragoza.com/agenda/",
            "https://auditoriozaragoza.com/",
        ):
            out = self.one(event(url=url), home_only=home)[0]
            self.assertEqual(out["moreInfoUrl"], "https://auditoriozaragoza.com/", url)
            self.assertFalse(out["hideLink"])
        fixed = self.one(event(), links={"7": "https://auditoriozaragoza.com/programacion/x/"}, home_only=home)[0]
        self.assertEqual(fixed["moreInfoUrl"], "https://auditoriozaragoza.com/")
        other = self.one(event(), home_only=home)[0]
        self.assertEqual(other["moreInfoUrl"], "https://teatro.example.org/")

    def test_una_web_sin_revisar_queda_sin_enlace(self):
        out = self.one(event(url="https://web-nueva.example.com/acto"))[0]
        self.assertTrue(out["hideLink"])
        self.assertEqual(out["moreInfoUrl"], "")
        fixed = self.one(event(), links={"7": "https://web-nueva.example.com/acto"})[0]
        self.assertTrue(fixed["hideLink"])

    def test_lista_de_webs_pendientes_de_revisar(self):
        events = [
            event("1", "https://web-nueva.example.com/a"),
            event("1", "https://web-nueva.example.com/a"),  # otra fecha del mismo acto
            event("2", "https://www.web-nueva.example.com/b"),
            event("3", "https://teatro.example.org/"),
            event("4", "https://prohibida.example.org/"),
            event("5", ""),
        ]
        found = lo.unreviewed_hosts(events, rules(blocked_hosts={"prohibida.example.org"}))
        self.assertEqual(list(found), ["web-nueva.example.com"])
        self.assertEqual(found["web-nueva.example.com"]["count"], 2)

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
            empty = rules(allowed_hosts=set())
            self.assertEqual(lo.load(path), empty)
            path.write_text("[1, 2", encoding="utf-8")
            self.assertEqual(lo.load(path), empty)

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
            self.assertNotIn(lo.host_of(url), data["home_only"], url)
            self.assertIn(lo.host_of(url), data["allowed_hosts"], url)
        self.assertFalse(data["allowed_hosts"] & data["blocked_hosts"])
        for home in data["home_only"].values():
            self.assertIn(lo.host_of(home), data["allowed_hosts"], home)


if __name__ == "__main__":
    unittest.main()
