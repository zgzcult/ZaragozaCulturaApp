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
    "guardia": {
        "fecha": "2026-10-06T00:00:00",
        "horario": "Abiertas de 9:15 h. a 9:15 h. del día siguiente",
        "sector": "Sector Gran Vía",
    },
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
    def test_farmacias_de_guardia_centros_de_salud_y_bibliotecas(self):
        data = services.collect_services(lambda url: {"result": [FARMACIA, FARMACIA]})
        self.assertEqual(
            [g["id"] for g in data["groups"]],
            ["farmacias-guardia", "centros-salud", "bibliotecas"],
        )
        self.assertEqual(data["groups"][1]["title"], "Centros Salud Públicos")
        self.assertEqual(data["groups"][2]["title"], "Bibliotecas municipales")
        # Ya no hay servicios de policía, aseos ni hospitales.
        self.assertNotIn("policia-local", [g["id"] for g in data["groups"]])
        self.assertEqual(len(data["groups"][0]["items"]), 1)  # sin duplicados

    def test_si_falla_el_ayuntamiento_los_centros_de_salud_siguen(self):
        def fetch(url):
            raise OSError("caído")

        groups = {g["id"]: g for g in services.collect_services(fetch)["groups"]}
        self.assertTrue(groups["farmacias-guardia"]["error"])
        self.assertEqual(len(groups["centros-salud"]["items"]), 34)
        self.assertNotIn("error", groups["centros-salud"])

    def test_centros_de_salud_del_listado_oficial(self):
        items = {i["name"]: i for i in services.health_centres()}
        almozara = items["Almozara"]
        self.assertEqual(almozara["address"], "Avda. Autonomía, 5, 50003 Zaragoza")
        self.assertEqual(almozara["call"], "876765120")
        self.assertIn("Cita previa: 976 306 841", almozara["info"])
        self.assertIn("Atención a domicilio: 876 765 121", almozara["info"])
        self.assertIn("Sector Zaragoza II", almozara["info"])
        self.assertEqual(almozara["url"], "")

    def test_solo_zaragoza_capital_con_los_tres_sectores(self):
        items = {i["name"]: i for i in services.health_centres()}
        for fuera in ("Sástago", "Campo de Belchite", "Fuentes de Ebro"):
            self.assertNotIn(fuera, items)
        for barrio in ("Actur Norte", "Picarral", "Delicias Sur", "Oliver", "Casetas", "Valdespartera"):
            self.assertIn(barrio, items)
        oliver = items["Oliver"]
        self.assertEqual(oliver["call"], "976346359")
        self.assertIn("Sector Zaragoza III", oliver["info"])
        self.assertNotIn("Cita previa", oliver["info"])  # la fuente no la indica
        # Sin enlace a las webs del Gobierno de Aragón: exigen autorización.
        for item in items.values():
            self.assertEqual(item["url"], "")


def _farmacia(i, fecha="2026-10-06T00:00:00"):
    f = dict(FARMACIA, id=i, title=f"Farmacia {i}")
    f["guardia"] = dict(FARMACIA["guardia"], fecha=fecha)
    return f


class GuardiaTests(unittest.TestCase):
    def test_solo_las_de_guardia_del_dia_mas_reciente(self):
        sin_guardia = {"id": 1, "title": "Farmacia normal", "calle": "Calle 1"}
        ayer = _farmacia(2, "2026-10-05T00:00:00")
        hoy = [_farmacia(10), _farmacia(11)]
        got = services.guard_pharmacies([sin_guardia, ayer] + hoy)
        self.assertEqual([g["id"] for g in got], [10, 11])

    def test_un_listado_enorme_no_se_enseña(self):
        # El caso real: salían 72 farmacias «de guardia».
        muchas = [_farmacia(i) for i in range(72)]
        with self.assertRaises(ValueError):
            services.guard_pharmacies(muchas)

    def test_el_grupo_falla_en_vez_de_mostrar_una_cifra_absurda(self):
        data = services.collect_services(lambda url: {"result": [_farmacia(i) for i in range(72)]})
        grupo = {g["id"]: g for g in data["groups"]}["farmacias-guardia"]
        self.assertTrue(grupo["error"])
        self.assertEqual(grupo["items"], [])

    def test_pide_solo_las_de_guardia(self):
        urls = []

        def fetch(url):
            urls.append(url)
            return {"result": [_farmacia(1)]}

        services.collect_services(fetch)
        self.assertIn("tipo=guardia", urls[0])

    def test_sin_farmacias_de_guardia_devuelve_vacio(self):
        self.assertEqual(services.guard_pharmacies([]), [])
        self.assertEqual(services.guard_pharmacies([{"id": 1, "title": "x"}]), [])


class LibraryTests(unittest.TestCase):
    def fetch(self, url):
        if url.endswith("/equipamiento/916.json"):
            return {"horario": "<ul><li>Lunes: de 15 a 21 h.</li><li>Sábados: de 9.30 a 14 h.</li></ul>"}
        raise OSError("sin respuesta")

    def test_27_bibliotecas_con_su_ficha_oficial(self):
        items = {i["name"]: i for i in services.libraries(self.fetch)}
        self.assertEqual(len(items), 27)
        jarnes = items["Biblioteca Benjamín Jarnés (Actur-Rey Fernando)"]
        self.assertEqual(jarnes["address"], "Calle Pedro Laín Entralgo 15, 50018 Zaragoza")
        self.assertEqual(jarnes["call"], "976726108")
        self.assertEqual(jarnes["url"], "https://www.zaragoza.es/sede/servicio/equipamiento/916")
        self.assertEqual(jarnes["horario"], "• Lunes: de 15 a 21 h.\n• Sábados: de 9.30 a 14 h.")

    def test_si_la_ficha_no_responde_se_muestra_sin_horario(self):
        items = services.libraries(self.fetch)
        otras = [i for i in items if not i["url"].endswith("/916")]
        self.assertTrue(all(i["horario"] == "" for i in otras))
        self.assertTrue(all(i["call"] for i in items))

    def test_datos_corregidos_con_la_web_oficial(self):
        items = {i["name"]: i for i in services.libraries(self.fetch)}
        self.assertEqual(items["Biblioteca de Casetas"]["call"], "876536521")
        self.assertIn("Andrés Gimeno 1,", items["Biblioteca de Montañana"]["address"])
        self.assertIn("Biblioteca Andresa Casamayor (Rosales del Canal)", items)

    def test_sin_mapas_ni_coordenadas(self):
        for item in services.libraries(self.fetch):
            self.assertIsNone(item["lat"])
            self.assertTrue(item["id"].startswith("bibliotecas-"))


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
