"""Pruebas de «Servicios útiles». Ejecutar con:

    python backend/test_services.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import services  # noqa: E402

FARMACIA = {
    "id": 8860,
    "title": "Farmacia Artal Lerín, Ana Cristina",
    "telefonos": "976226203",
    "horario": "Lunes a Domingo 24 horas",
    "calle": "Pº. de Sagasta, 8",
    "geometry": {"type": "Point", "coordinates": [-0.8858667, 41.6461463]},
    "guardia": {"horario": "Abiertas de 9:15 h. a 9:15 h. del día siguiente", "sector": "Sector Gran Vía"},
}

POLICIA = {
    "id": 449,
    "title": "Central de operaciones de Policía Local",
    "tel": {"tel": "092 976 724100", "fax": "976 723505"},
    "calle": "C/ Domingo Miral , 1",
    "horario": "<p>Servicio las <strong>24 horas</strong>.</p>",
    "geometry": {"type": "Point", "coordinates": [674238.49, 4612832.19]},
    "link": "https://www.zaragoza.es/sede/servicio/equipamiento/449",
}

BANO = {
    "id": 11893,
    "title": "Baño Público en Parque Grande 1",
    "precio": "El coste del servicio es de 0,30 céntimos",
    "calle": "Parque José Antonio Labordeta",
    "uri": "http://www.zaragoza.es/sede/servicio/equipamiento/11893",
}


class PhoneTests(unittest.TestCase):
    def test_primer_telefono_de_nueve_cifras(self):
        self.assertEqual(services.first_phone("092 976 724100"), "976724100")
        self.assertEqual(services.first_phone("976 72 12 21 - Reservas 976 72 60 75"), "976721221")
        self.assertEqual(services.first_phone("976.226.203"), "976226203")
        self.assertEqual(services.first_phone(""), "")
        self.assertEqual(services.first_phone("Sin teléfono"), "")


class NormalizeTests(unittest.TestCase):
    def test_farmacia_de_guardia(self):
        item = services.normalize_service("farmacias-guardia", FARMACIA)
        self.assertEqual(item["id"], "farmacias-guardia-8860")
        self.assertEqual(item["address"], "Pº. de Sagasta, 8")
        self.assertEqual(item["call"], "976226203")
        self.assertIn("De guardia: Abiertas de 9:15", item["info"])
        self.assertIn("Sector Gran Vía", item["info"])
        self.assertAlmostEqual(item["lat"], 41.646146, places=4)

    def test_policia_sin_html_y_coordenadas_ed50(self):
        item = services.normalize_service("policia-local", POLICIA)
        self.assertEqual(item["phone"], "092 976 724100")
        self.assertEqual(item["call"], "976724100")
        self.assertEqual(item["horario"], "Servicio las 24 horas.")
        self.assertEqual(item["url"], "https://www.zaragoza.es/sede/servicio/equipamiento/449")
        self.assertIsNotNone(item["lat"])

    def test_bano_con_precio_y_sin_coordenadas(self):
        item = services.normalize_service("aseos", BANO)
        self.assertEqual(item["info"], "El coste del servicio es de 0,30 céntimos")
        self.assertEqual(item["call"], "")
        self.assertIsNone(item["lat"])
        self.assertTrue(item["url"].startswith("https://"))

    def test_sin_nombre_se_descarta(self):
        self.assertIsNone(services.normalize_service("aseos", {"id": 1, "title": " "}))


class CollectTests(unittest.TestCase):
    def test_todos_los_grupos_en_orden_y_un_fallo_no_estropea_el_resto(self):
        def fetch(url):
            if "farmacia" in url:
                return {"result": [FARMACIA]}
            if "/category/94." in url:
                return {"equipamiento": [POLICIA, POLICIA]}  # duplicado
            if "/category/760." in url:
                raise OSError("caído")
            if "/category/1060." in url:
                return {"equipamiento": [BANO]}
            return {"equipamiento": []}

        data = services.collect_services(fetch)
        ids = [g["id"] for g in data["groups"]]
        self.assertEqual(
            ids,
            ["farmacias-guardia", "hospitales", "centros-salud", "policia-local", "policia-nacional", "aseos"],
        )
        groups = {g["id"]: g for g in data["groups"]}
        self.assertEqual(len(groups["farmacias-guardia"]["items"]), 1)
        self.assertEqual(len(groups["policia-local"]["items"]), 1)
        self.assertTrue(groups["policia-nacional"]["error"])
        self.assertEqual(groups["policia-nacional"]["items"], [])
        self.assertEqual(len(groups["aseos"]["items"]), 1)
        self.assertNotIn("error", groups["aseos"])


class ServerCacheTests(unittest.TestCase):
    def test_si_un_grupo_falla_la_cache_dura_poco(self):
        os.environ.setdefault("MONGODB_URI", "")
        import server

        calls = []

        def collect():
            calls.append(1)
            return {"updated": "x", "groups": [{"id": "a", "title": "A", "items": [], "error": True}]}

        server._services_cache.clear()
        server.get_services_payload(collect)
        expires = server._services_cache["all"][0]
        self.assertLess(expires - server.time.time(), 6 * 60)
        server.get_services_payload(collect)
        self.assertEqual(len(calls), 1)  # la segunda vez sale de la caché
        server._services_cache.clear()


if __name__ == "__main__":
    unittest.main()
