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


if __name__ == "__main__":
    unittest.main()
