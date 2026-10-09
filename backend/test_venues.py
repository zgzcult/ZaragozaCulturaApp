"""Pruebas de los datos del lugar que entrega el servidor. Ejecutar con:

    python backend/test_venues.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server  # noqa: E402


class VenuesTests(unittest.TestCase):
    def test_un_registro_por_lugar_con_lo_que_haya(self):
        events = [
            {"place": "Centro de Historias", "venuePhone": "976 721 885", "venueTransport": "22, 35, 36"},
            {"place": "Centro de Historias", "venuePhone": "976 721 885"},
            {"place": "Plaza del Pilar"},
            {"place": "", "venuePhone": "976 000 000"},
            {"place": "Auditorio", "venueAccessibility": "Ascensor adaptado: SI"},
        ]
        self.assertEqual(
            server.venues_from(events),
            {
                "Centro de Historias": {"phone": "976 721 885", "transport": "22, 35, 36"},
                "Auditorio": {"accessibility": "Ascensor adaptado: SI"},
            },
        )

    def test_la_agenda_no_repite_esos_datos(self):
        self.assertEqual(set(server.VENUE_FIELDS), {"venuePhone", "venueTransport", "venueAccessibility"})


if __name__ == "__main__":
    unittest.main()
