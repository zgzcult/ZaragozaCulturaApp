"""Pruebas de las descripciones propias. Ejecutar con:

    python backend/test_rewrites.py
"""

import os
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rewrites  # noqa: E402

TODAY = date(2026, 10, 8)
ORIGINAL = "Texto  del\nAyuntamiento."
KEY = rewrites.text_key(ORIGINAL)


def event(day, description=ORIGINAL, **extra):
    return {"id": f"e-{day}", "title": "Concierto", "date": day, "description": description, **extra}


class TextKeyTest(unittest.TestCase):
    def test_ignora_espacios_y_saltos(self):
        self.assertEqual(KEY, rewrites.text_key(" Texto del Ayuntamiento. "))
        self.assertEqual(len(KEY), 16)

    def test_texto_distinto_huella_distinta(self):
        self.assertNotEqual(KEY, rewrites.text_key("Texto del Ayuntamiento, cambiado."))

    def test_sin_texto_no_hay_huella(self):
        self.assertEqual(rewrites.text_key(""), "")
        self.assertEqual(rewrites.text_key("  \n "), "")
        self.assertEqual(rewrites.text_key(None), "")


class PublishTest(unittest.TestCase):
    def test_con_texto_propio_se_publica_reescrita(self):
        out = rewrites.publish([event("2026-11-20")], {KEY: "Texto propio."}, TODAY)
        self.assertEqual([e["description"] for e in out], ["Texto propio."])

    def test_sin_texto_propio_y_lejana_no_se_publica(self):
        self.assertEqual(rewrites.publish([event("2026-10-12")], {}, TODAY), [])

    def test_sin_texto_propio_y_cercana_sale_sin_descripcion(self):
        out = rewrites.publish([event("2026-10-08"), event("2026-10-11")], {}, TODAY)
        self.assertEqual([e["description"] for e in out], ["", ""])

    def test_nunca_sale_el_texto_original(self):
        events = [event("2026-10-08"), event("2026-10-30"), event("2026-11-20")]
        for known in ({}, {KEY: "Texto propio."}):
            for e in rewrites.publish(events, known, TODAY):
                self.assertNotIn("Ayuntamiento", e["description"])

    def test_sin_descripcion_se_publica_tal_cual(self):
        out = rewrites.publish([event("2026-11-20", description="")], {}, TODAY)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["description"], "")

    def test_el_aviso_de_sin_descripcion_se_deja_en_blanco(self):
        empty = event("2026-11-20", description=rewrites.NO_DESCRIPTION)
        out = rewrites.publish([empty], {}, TODAY)
        self.assertEqual([e["description"] for e in out], [""])
        self.assertEqual(rewrites.pending([empty], {}), [])

    def test_las_actividades_propias_no_se_tocan(self):
        own = event("2026-11-20", source="propio")
        self.assertEqual(rewrites.publish([own], {}, TODAY), [own])

    def test_no_modifica_la_actividad_original(self):
        source = event("2026-11-20")
        rewrites.publish([source], {KEY: "Texto propio."}, TODAY)
        self.assertEqual(source["description"], ORIGINAL)


class PendingTest(unittest.TestCase):
    def test_un_texto_por_huella(self):
        events = [event("2026-10-10"), event("2026-10-11"), event("2026-10-12", description="Otro texto.")]
        items = rewrites.pending(events, {})
        self.assertEqual([i["key"] for i in items], [KEY, rewrites.text_key("Otro texto.")])
        self.assertEqual(items[0]["description"], ORIGINAL)

    def test_los_ya_reescritos_no_estan_pendientes(self):
        self.assertEqual(rewrites.pending([event("2026-10-10")], {KEY: "Texto propio."}), [])

    def test_ni_los_vacios_ni_los_propios(self):
        events = [event("2026-10-10", description=""), event("2026-10-10", source="propio")]
        self.assertEqual(rewrites.pending(events, {}), [])

    def test_huellas_en_uso(self):
        events = [event("2026-10-10"), event("2026-10-11"), event("2026-10-12", description="")]
        self.assertEqual(rewrites.live_keys(events), [KEY])


class LoadTest(unittest.TestCase):
    def test_fichero_ausente_o_roto(self):
        with tempfile.TemporaryDirectory() as folder:
            missing = Path(folder) / "no.json"
            self.assertEqual(rewrites.load(missing), {})
            missing.write_text("{roto", encoding="utf-8")
            self.assertEqual(rewrites.load(missing), {})

    def test_descarta_entradas_vacias(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "r.json"
            path.write_text('{"a": "Texto.", "b": " ", "c": 3}', encoding="utf-8")
            self.assertEqual(rewrites.load(path), {"a": "Texto."})

    def test_el_fichero_del_repositorio_es_valido(self):
        if not rewrites.PATH.exists():
            self.skipTest("rewrites.json aún no existe")
        data = rewrites.load()
        self.assertTrue(data)
        for key, text in data.items():
            self.assertEqual(len(key), 16, key)
            self.assertGreater(len(text), 20, key)


if __name__ == "__main__":
    unittest.main()
