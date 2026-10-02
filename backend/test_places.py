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
    def test_ed50_coincide_con_pyproj(self):
        # Valores de referencia calculados con pyproj (EPSG:23030 -> EPSG:4326).
        referencia = {
            (671271.45, 4615302.48): (41.6692157, -0.9439177),
            (676934.75, 4613880.67): (41.6551808, -0.8763531),
            (675000.0, 4612000.0): (41.6386796, -0.9001241),
        }
        for (east, north), (lat, lng) in referencia.items():
            got = places.ed50_utm_to_latlng(east, north)
            metros = (((got[0] - lat) * 111000) ** 2 + ((got[1] - lng) * 83000) ** 2) ** 0.5
            self.assertLess(metros, 1.0, (east, north, got))

    def test_museo_del_foro_coincide_con_el_otro_conjunto_de_datos(self):
        # La agenda cultural da ese museo en (41.655183, -0.876353).
        lat, lng = places.ed50_utm_to_latlng(676934.75, 4613880.67)
        self.assertAlmostEqual(lat, 41.655183, places=4)
        self.assertAlmostEqual(lng, -0.876353, places=4)


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
        self.assertAlmostEqual(place["lat"], 41.669216, places=4)
        self.assertAlmostEqual(place["lng"], -0.943918, places=4)
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


class CleanAddressTests(unittest.TestCase):
    def test_abreviaturas(self):
        self.assertEqual(places.clean_address("C/ Madre Vedruna, 10"), "Calle Madre Vedruna 10")
        self.assertEqual(places.clean_address("Avda. Salvador Allende, 75"), "Avenida Salvador Allende 75")
        self.assertEqual(places.clean_address("Pº de la Noria, 3"), "Paseo de la Noria 3")
        self.assertEqual(places.clean_address("Ctra. de Logroño Km. 1,500"), "Carretera de Logroño Km. 1 500")

    def test_tipo_de_via_entre_parentesis(self):
        self.assertEqual(places.clean_address("Gertrudis Gomez Avellaneda (Avenida), 43"), "Avenida Gertrudis Gomez Avellaneda 43")
        self.assertEqual(places.clean_address("San Francisco (Plaza), 09 (esquina Andres Piquer)"), "Plaza San Francisco 9")

    def test_quita_esquinas_locales_y_centros_comerciales(self):
        self.assertEqual(places.clean_address("C/ Duquesa Villahermosa, 42 (esquina C/ Delicias)"), "Calle Duquesa Villahermosa 42")
        self.assertEqual(places.clean_address("C/ Coso, 35 - CC. Puerta Cinegia, planta 1ª, puestos 17 y 18"), "Calle Coso 35")
        self.assertEqual(places.clean_address("La Ventana Indiscreta, 8, local"), "La Ventana Indiscreta 8")

    def test_rangos_y_sin_numero(self):
        self.assertEqual(places.clean_address("C/ Bruil, 4-6"), "Calle Bruil 4")
        self.assertEqual(places.clean_address("C/ Mayor s/n"), "Calle Mayor")
        self.assertEqual(places.clean_address(""), "")


def portal(address="CALLE BRUIL, JUAN 4", lat=41.6485, lng=-0.8837, **extra):
    data = {"type": "portal", "address": address, "muni": "Zaragoza", "lat": lat, "lng": lng, "noNumber": False}
    data.update(extra)
    return data


class GeocodeTests(unittest.TestCase):
    def test_acepta_un_portal_correcto(self):
        self.assertEqual(places.geocode_address("C/ Bruil, 4-6", "50001", lambda q: portal()), (41.6485, -0.8837))

    def test_rechaza_otra_ciudad(self):
        far = portal(muni="Madrid", lat=40.4, lng=-3.7)
        self.assertIsNone(places.geocode_address("C/ Bruil, 4", "50001", lambda q: far))

    def test_rechaza_coordenadas_fuera_de_zaragoza_aunque_diga_zaragoza(self):
        self.assertIsNone(places.geocode_address("C/ Bruil, 4", "50001", lambda q: portal(lat=40.4, lng=-3.7)))

    def test_rechaza_calle_distinta_a_la_pedida(self):
        self.assertIsNone(places.geocode_address("C/ Bruil, 4", "50001", lambda q: portal(address="PRUDENCIO")))

    def test_rechaza_resultados_que_no_son_un_portal(self):
        self.assertIsNone(places.geocode_address("C/ Bruil, 4", "50001", lambda q: portal(type="callejero")))
        self.assertIsNone(places.geocode_address("C/ Bruil", "50001", lambda q: portal(noNumber=True)))

    def test_prueba_sin_codigo_postal_si_falla_con_el_(self):
        queries = []

        def find(q):
            queries.append(q)
            return portal() if "50099" not in q else None

        self.assertIsNotNone(places.geocode_address("C/ Bruil, 4", "50099", find))
        self.assertEqual(len(queries), 2)


def sin_ubicacion(street, postal="50001", pid="1"):
    return {"id": f"restaurante-{pid}", "street": street, "postal": postal, "lat": None, "lng": None, "locSource": ""}


class FindTests(unittest.TestCase):
    class FakeResponse:
        def __init__(self, body):
            self.body = body

        def read(self):
            return self.body

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    def call(self, body):
        from unittest import mock

        with mock.patch.object(places.urllib.request, "urlopen", return_value=self.FakeResponse(body)):
            return places.cartociudad_find("Calle Inventada 1, Zaragoza")

    def test_cuerpo_vacio_es_sin_resultado_y_no_un_error(self):
        self.assertIsNone(self.call(b""))
        self.assertIsNone(self.call(b"  \n"))

    def test_respuesta_no_json_es_sin_resultado(self):
        self.assertIsNone(self.call(b"<html>error</html>"))

    def test_respuesta_valida(self):
        self.assertEqual(self.call(b'{"lat": 41.6, "lng": -0.9, "type": "portal"}')["type"], "portal")

    def test_los_errores_de_red_siguen_siendo_errores(self):
        from unittest import mock

        with mock.patch.object(places.urllib.request, "urlopen", side_effect=OSError("sin red")):
            with self.assertRaises(OSError):
                places.cartociudad_find("x")


class GeocodePlacesTests(unittest.TestCase):
    def setUp(self):
        self.calls = []

    def find(self, q):
        self.calls.append(q)
        return portal()

    def run_geo(self, items, cache=None, **kw):
        return places.geocode_places(items, {} if cache is None else cache, find=self.find, pause=lambda _: None, **kw)

    def test_ubica_los_que_no_tienen_coordenadas(self):
        items = [sin_ubicacion("C/ Bruil, 4")]
        stats = self.run_geo(items)
        self.assertEqual((items[0]["lat"], items[0]["lng"]), (41.6485, -0.8837))
        self.assertEqual(items[0]["locSource"], "cartociudad")
        self.assertEqual(stats["placed"], 1)

    def test_no_toca_los_que_ya_tienen_coordenadas(self):
        item = {"id": "a", "street": "C/ Bruil, 4", "postal": "50001", "lat": 41.7, "lng": -0.9, "locSource": "ayuntamiento"}
        self.run_geo([item])
        self.assertEqual(self.calls, [])
        self.assertEqual(item["lat"], 41.7)

    def test_usa_la_cache_y_no_repite_consultas(self):
        cache = {}
        self.run_geo([sin_ubicacion("C/ Bruil, 4")], cache)
        first = len(self.calls)
        again = [sin_ubicacion("C/ Bruil, 4", pid="2")]
        stats = self.run_geo(again, cache)
        self.assertEqual(len(self.calls), first)
        self.assertEqual(stats["from_cache"], 1)
        self.assertEqual(again[0]["lat"], 41.6485)

    def test_los_no_encontrados_se_guardan_y_se_reintentan_a_los_30_dias(self):
        cache = {}
        nothing = lambda q: None
        items = [sin_ubicacion("C/ Inventada, 1")]
        now = places.datetime(2026, 10, 1, tzinfo=places.timezone.utc)
        places.geocode_places(items, cache, find=nothing, pause=lambda _: None, now=now)
        self.assertEqual(len(cache), 1)
        calls = []
        places.geocode_places(items, cache, find=lambda q: calls.append(q), pause=lambda _: None, now=now + places.timedelta(days=5))
        self.assertEqual(calls, [])  # aún no toca reintentar
        places.geocode_places(items, cache, find=lambda q: calls.append(q), pause=lambda _: None, now=now + places.timedelta(days=31))
        self.assertTrue(calls)  # ya sí

    def test_un_fallo_de_red_no_se_guarda_en_la_cache(self):
        def broken(q):
            raise OSError("sin conexión")

        cache = {}
        items = [sin_ubicacion("C/ Bruil, 4")]
        stats = places.geocode_places(items, cache, find=broken, pause=lambda _: None)
        self.assertEqual(stats["errors"], 1)
        self.assertEqual(cache, {})
        self.assertIsNone(items[0]["lat"])

    def test_limita_el_numero_de_consultas(self):
        items = [sin_ubicacion(f"C/ Bruil, {n}", pid=str(n)) for n in range(1, 8)]
        stats = self.run_geo(items, max_calls=3)
        self.assertEqual(stats["calls"], 3)


def raw_monument(**overrides):
    data = {
        "id": 2,
        "title": "Museo del Foro de Caesaraugusta",
        "description": "El Foro es el centro <strong>neurálgico</strong>.\r\n<p>Segundo&nbsp;párrafo.</p>",
        "estilo": "romano",
        "address": "Plaza de la Seo, 2",
        "horario": "Martes a sábado de 10 a 14h\r\nLunes cerrado",
        "phone": "976 72 12 21",
        "datacion": "Siglo I a.C. - Siglo I d.C.",
        "price": "<em>Entrada</em>: 3 euros",
        "image": "http://www.zaragoza.es/azar/img/monumentos/forop.jpg",
        "top": "S",
        "geometry": {"type": "Point", "coordinates": [676934.75, 4613880.67]},
        "uri": "https://www.zaragoza.es/sede/portal/turismo/servicio/monumento/2",
    }
    data.update(overrides)
    return data


class MonumentTests(unittest.TestCase):
    def test_monumento_completo(self):
        m = places.normalize_place("monumento", raw_monument())
        self.assertEqual(m["id"], "monumento-2")
        self.assertEqual(m["type"], "monumento")
        self.assertEqual(m["name"], "Museo del Foro de Caesaraugusta")
        self.assertEqual(m["address"], "Plaza de la Seo, 2")
        self.assertEqual(m["phone"], "976 72 12 21")
        self.assertAlmostEqual(m["lat"], 41.655183, places=4)
        self.assertEqual(m["styles"], ["Romano"])
        self.assertEqual(m["datacion"], "Siglo I a.C. - Siglo I d.C.")
        self.assertTrue(m["museum"])
        self.assertTrue(m["top"])
        # Página oficial y foto, siempre por https.
        self.assertEqual(m["url"], "https://www.zaragoza.es/sede/portal/turismo/servicio/monumento/2")
        self.assertEqual(m["image"], "https://www.zaragoza.es/azar/img/monumentos/forop.jpg")

    def test_textos_oficiales_sin_html_y_sin_cambiar_la_redaccion(self):
        m = places.normalize_place("monumento", raw_monument())
        self.assertEqual(m["description"], "El Foro es el centro neurálgico.\n\nSegundo párrafo.")
        self.assertEqual(m["horario"], "Martes a sábado de 10 a 14h\nLunes cerrado")
        self.assertEqual(m["price"], "Entrada: 3 euros")

    def test_listas_e_imagenes_del_html(self):
        text = places.html_to_text('<p><img src="/x.jpg" alt=""/> Accesible</p><ul><li>Uno</li><li>Dos</li></ul>')
        self.assertEqual(text, "Accesible\n\n• Uno\n• Dos")

    def test_sin_coordenadas_usa_la_direccion(self):
        m = places.normalize_place("monumento", raw_monument(geometry=None))
        self.assertIsNotNone(m)
        self.assertIsNone(m["lat"])
        self.assertEqual(m["street"], "Plaza de la Seo, 2")

    def test_grupos_de_estilo(self):
        self.assertEqual(places.style_groups("barroco, neoclasico"), ["Barroco", "Neoclásico"])
        self.assertEqual(places.style_groups("Románico, Gótico, Mudéjar"), ["Medieval", "Mudéjar"])
        # Un neomudéjar del siglo XIX es contemporáneo, no mudéjar.
        self.assertEqual(places.style_groups("contemporaneo: historicismo Neomudéjar"), ["Contemporáneo"])
        self.assertEqual(places.style_groups("Comtemporáneo"), ["Contemporáneo"])
        self.assertEqual(places.style_groups("entorno"), ["Naturaleza"])
        self.assertEqual(places.style_groups(""), [])

    def test_no_es_museo_ni_imprescindible(self):
        m = places.normalize_place("monumento", raw_monument(title="Iglesia de San Pablo", top=None, image="ftp://x"))
        self.assertFalse(m["museum"])
        self.assertFalse(m["top"])
        self.assertEqual(m["image"], "")

    def test_los_restaurantes_no_llevan_campos_de_monumento(self):
        self.assertNotIn("description", places.normalize_place("restaurante", raw()))

    def test_limpieza_por_tipo_con_su_minimo(self):
        col = FakeCollection([f"r{i}" for i in range(300)])
        col.docs.update({f"m{i}": {"id": f"m{i}", "type": "monumento"} for i in range(150)})
        col.docs["m-viejo"] = {"id": "m-viejo", "type": "monumento"}
        monuments = [{"id": f"m{i}", "type": "monumento"} for i in range(150)]
        places.save("monumento", monuments, col)
        self.assertNotIn("m-viejo", col.docs)
        # Los restaurantes no se tocan.
        self.assertEqual(sum(1 for d in col.docs.values() if d.get("type") == "restaurante"), 300)


if __name__ == "__main__":
    unittest.main()
