"""Pruebas de la descarga de lugares. Ejecutar con:

    python backend/test_places.py
"""

import importlib.util
import os
import unittest

spec = importlib.util.spec_from_file_location("places", os.path.join(os.path.dirname(__file__), "scraper", "places.py"))
places = importlib.util.module_from_spec(spec)
spec.loader.exec_module(places)


def raw(**overrides):
    data = {
        "id": 14,
        "title": "RESTAURANTE EL CACHIRULO",
        "streetAddress": "Ctra. de Logroño Km. 1,500",
        "postalCode": "50011",
        "tel": {"tel": "976 460 146"},
        "url": "http://www.elcachirulo.es/restaurante/",
        "geometry": {"type": "Point", "coordinates": [671271.45, 4615302.48]},
    }
    data.update(overrides)
    return data


class UtmTests(unittest.TestCase):
    def test_coincide_con_pyproj(self):
        # Valores calculados con pyproj (EPSG:25830 -> EPSG:4326).
        for (east, north), (lat, lng) in {
            (676934.75, 4613880.67): (41.657043, -0.874992),
            (671271.45, 4615302.48): (41.671079, -0.942558),
            (675000.0, 4612000.0): (41.640542, -0.898763),
            (680000.0, 4618000.0): (41.693434, -0.836961),
        }.items():
            got = places.utm_to_latlng(east, north)
            self.assertAlmostEqual(got[0], lat, places=5)
            self.assertAlmostEqual(got[1], lng, places=5)


class NameTests(unittest.TestCase):
    def test_limpia_mayusculas_y_prefijo(self):
        self.assertEqual(places.clean_name("RESTAURANTE EL CACHIRULO"), "El Cachirulo")
        self.assertEqual(places.clean_name("BAR LA MAÑANA DE LOS AMIGOS"), "Bar la Mañana de los Amigos")

    def test_respeta_nombres_ya_bien_escritos(self):
        self.assertEqual(places.clean_name("Casa Lac"), "Casa Lac")
        self.assertEqual(places.clean_name("La Ternasca"), "La Ternasca")

    def test_nombre_vacio(self):
        self.assertEqual(places.clean_name("  "), "")


class NormalizeTests(unittest.TestCase):
    def test_lugar_completo(self):
        place = places.normalize_place("restaurante", raw())
        self.assertEqual(place["id"], "restaurante-14")
        self.assertEqual(place["name"], "El Cachirulo")
        self.assertEqual(place["address"], "Ctra. de Logroño Km. 1,500, 50011")
        self.assertEqual(place["phone"], "976 460 146")
        self.assertEqual((place["lat"], place["lng"]), (41.671079, -0.942558))
        self.assertEqual(place["source"], "ayuntamiento")

    def test_sin_coordenadas_se_guarda_para_la_lista(self):
        for geometry in (None, {"coordinates": []}):
            place = places.normalize_place("restaurante", raw(geometry=geometry))
            self.assertIsNotNone(place)
            self.assertIsNone(place["lat"])
            self.assertIsNone(place["lng"])
            self.assertEqual(place["address"], "Ctra. de Logroño Km. 1,500, 50011")

    def test_sin_coordenadas_ni_direccion_se_descarta(self):
        self.assertIsNone(places.normalize_place("restaurante", raw(geometry=None, streetAddress="", postalCode="")))

    def test_coordenadas_fuera_de_zaragoza_se_ignoran_pero_se_conserva_el_lugar(self):
        for coords in ([0.0, 0.0], [100.0, 10.0]):
            place = places.normalize_place("restaurante", raw(geometry={"coordinates": coords}))
            self.assertIsNotNone(place)
            self.assertIsNone(place["lat"])

    def test_coordenadas_en_grados(self):
        place = places.normalize_place("restaurante", raw(geometry={"coordinates": [-0.8773, 41.6563]}))
        self.assertEqual((place["lat"], place["lng"]), (41.6563, -0.8773))

    def test_web_invalida_se_ignora(self):
        self.assertEqual(places.normalize_place("restaurante", raw(url="elcachirulo.es"))["url"], "")

    def test_sin_nombre_se_descarta(self):
        self.assertIsNone(places.normalize_place("restaurante", raw(title="   ")))


class CollectTests(unittest.TestCase):
    def test_recorre_todas_las_paginas_y_quita_duplicados(self):
        pages = {
            0: {"totalCount": places.PAGE_SIZE + 2, "result": [raw(id=1), raw(id=2)]},
            places.PAGE_SIZE: {"totalCount": places.PAGE_SIZE + 2, "result": [raw(id=2), raw(id=3)]},
        }
        calls = []

        def fetch(kind, start):
            calls.append(start)
            return pages.get(start, {"totalCount": places.PAGE_SIZE + 2, "result": []})

        original_pause = places.time.sleep
        places.time.sleep = lambda _: None
        try:
            # El total es mayor que una página: debe pedir la segunda y parar.
            collected = places.collect("restaurante", fetch)
        finally:
            places.time.sleep = original_pause
        self.assertEqual(sorted(p["id"] for p in collected), ["restaurante-1", "restaurante-2", "restaurante-3"])
        self.assertEqual(calls[:2], [0, places.PAGE_SIZE])


class FakeCollection:
    def __init__(self, ids):
        self.docs = {i: {"id": i, "type": "restaurante"} for i in ids}

    def update_one(self, query, update, upsert=False):
        self.docs[query["id"]] = update["$set"]

    def find(self, query, proj):
        return [{"id": i} for i, d in self.docs.items() if d.get("type") == query["type"]]

    def delete_many(self, query):
        for i in query["id"]["$in"]:
            self.docs.pop(i, None)


def fresh(ids):
    return [{"id": i, "type": "restaurante"} for i in ids]


class SaveTests(unittest.TestCase):
    def test_borra_los_obsoletos(self):
        col = FakeCollection([f"r{i}" for i in range(300)] + ["viejo"])
        places.save("restaurante", fresh([f"r{i}" for i in range(300)]), col)
        self.assertNotIn("viejo", col.docs)
        self.assertEqual(len(col.docs), 300)

    def test_no_limpia_si_hay_pocos(self):
        col = FakeCollection(["a", "b", "c", "viejo"])
        places.save("restaurante", fresh(["a", "b", "c"]), col)
        self.assertIn("viejo", col.docs)

    def test_cancela_si_borraria_demasiado(self):
        col = FakeCollection([f"r{i}" for i in range(1000)])
        places.save("restaurante", fresh([f"r{i}" for i in range(250)]), col)
        self.assertEqual(len(col.docs), 1000)


if __name__ == "__main__":
    unittest.main()
