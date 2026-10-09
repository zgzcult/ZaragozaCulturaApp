"""Pruebas del scraper de la agenda. Ejecutar con:

    python backend/test_scraper.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "scraper"))
import scraper  # noqa: E402


def fare(group, value):
    return {"fareGroup": group, "hasCurrencyValue": value, "hasCurrency": "EUR", "minSize": "1"}


class FreeTests(unittest.TestCase):
    def test_gratuita_declarada(self):
        self.assertTrue(scraper.is_free({"price": [fare("Gratuita", 0)]}))

    def test_todas_las_tarifas_a_cero(self):
        self.assertTrue(scraper.is_free({"price": [fare("Normal", 0), fare("Reducida", 0.0)]}))

    def test_de_pago(self):
        self.assertFalse(scraper.is_free({"price": [fare("Normal", 15)]}))
        # Una tarifa gratuita y otra de pago: no es gratis para todos.
        self.assertFalse(scraper.is_free({"price": [fare("Gratuita", 0), fare("Normal", 3)]}))

    def test_sin_precio_publicado_no_se_da_por_gratis(self):
        self.assertFalse(scraper.is_free({}))
        self.assertFalse(scraper.is_free({"price": []}))
        self.assertFalse(scraper.is_free({"price": "gratis"}))
        self.assertFalse(scraper.is_free({"price": [fare("Normal", None)]}))

    def test_cada_dia_de_la_actividad_lleva_el_dato(self):
        from datetime import datetime, timedelta

        tomorrow = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%dT00:00:00")
        source = {
            "id": 1,
            "title": "Concierto gratis",
            "startDate": tomorrow,
            "endDate": tomorrow,
            "price": [fare("Gratuita", 0)],
        }
        events = scraper.dataset_event_occurrences(source, limit=5)
        self.assertTrue(events)
        self.assertTrue(all(e["free"] is True for e in events))
        source["price"] = [fare("Normal", 10)]
        self.assertTrue(all(e["free"] is False for e in scraper.dataset_event_occurrences(source, limit=5)))


def activity(**extra):
    from datetime import datetime, timedelta

    tomorrow = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%dT00:00:00")
    return {
        "id": 7,
        "title": "Ofrenda subacuática",
        "startDate": tomorrow,
        "endDate": tomorrow,
        "subEvent": [{"id": 1, "location": {"id": 6011, "title": "Acuario"}}],
        **extra,
    }


FICHA = "https://www.zaragoza.es/sede/servicio/cultura/evento/7"


class VenueWebsiteTests(unittest.TestCase):
    def links(self, source, records):
        calls = []

        def load(venue_id):
            calls.append(venue_id)
            return records[venue_id]

        lookup = scraper.VenueWebsites(load)
        events = scraper.dataset_event_occurrences(source, limit=5, venue_website=lookup)
        events += scraper.dataset_event_occurrences(source, limit=5, venue_website=lookup)
        return {e["moreInfoUrl"] for e in events}, calls

    def test_sin_enlace_propio_va_a_la_web_del_lugar(self):
        links, calls = self.links(activity(), {"6011": {"url": "http://www.acuariodezaragoza.com/"}})
        self.assertEqual(links, {"http://www.acuariodezaragoza.com/"})
        self.assertEqual(calls, ["6011"])  # una sola consulta por lugar

    def test_el_enlace_propio_de_la_actividad_manda(self):
        source = activity(moreInfoUrl="https://entradas.example.org/ofrenda")
        links, calls = self.links(source, {"6011": {"url": "http://www.acuariodezaragoza.com/"}})
        self.assertEqual(links, {"https://entradas.example.org/ofrenda"})
        self.assertEqual(calls, [])

    def test_lugar_municipal_o_sin_web_se_queda_en_la_ficha(self):
        for record in ({}, {"url": ""}, {"url": "https://www.zaragoza.es/sede/portal/museos/"}, {"url": "no es una web"}):
            links, _ = self.links(activity(), {"6011": record})
            self.assertEqual(links, {FICHA}, record)

    def test_si_la_consulta_falla_se_queda_en_la_ficha(self):
        def broken(_venue_id):
            raise ValueError("respuesta rota")

        events = scraper.dataset_event_occurrences(activity(), limit=5, venue_website=scraper.VenueWebsites(broken))
        self.assertEqual({e["moreInfoUrl"] for e in events}, {FICHA})

    def test_web_sin_protocolo(self):
        self.assertEqual(scraper.external_url("www.teatro.example.com"), "https://www.teatro.example.com")
        self.assertEqual(scraper.external_url("https://museos.zaragoza.es/x"), "")
        self.assertEqual(scraper.external_url(None), "")


class VenueDetailsTests(unittest.TestCase):
    LOCATION = {
        "id": 6011,
        "title": "Centro de Historias",
        "telephone": "976 721 885 ",
        "publicTransport": "22, 35,\r\n36",
        "accessibility": "<div><img alt='Accesible' src='x.jpg' /> Accesible</div><p>Aseos adaptados: <b>Sí</b></p>",
    }

    def test_limpia_y_guarda_solo_lo_que_hay(self):
        details = scraper.venue_details(self.LOCATION)
        self.assertEqual(details["venuePhone"], "976 721 885")
        self.assertEqual(details["venueTransport"], "22, 35, 36")
        self.assertNotIn("<", details["venueAccessibility"])
        self.assertIn("Aseos adaptados", details["venueAccessibility"])
        self.assertEqual(scraper.venue_details({"title": "Plaza"}), {})
        self.assertEqual(scraper.venue_details("Plaza del Pilar"), {})

    def test_cada_sesion_lleva_los_datos_del_lugar(self):
        source = activity()
        source["subEvent"][0]["location"] = self.LOCATION
        events = scraper.dataset_event_occurrences(source, limit=5)
        self.assertTrue(events)
        self.assertEqual(events[0]["venuePhone"], "976 721 885")
        plain = scraper.dataset_event_occurrences(activity(), limit=5)
        self.assertNotIn("venuePhone", plain[0])


if __name__ == "__main__":
    unittest.main()
