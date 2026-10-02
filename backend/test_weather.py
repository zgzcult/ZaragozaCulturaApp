"""Pruebas de la temperatura de AEMET. Ejecutar con:

    python backend/test_weather.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weather  # noqa: E402

OBS = [
    {"fint": "2026-10-02T14:00:00+0000", "ta": 21.4},
    {"fint": "2026-10-02T16:00:00+0000", "ta": None},
    {"fint": "2026-10-02T15:00:00+0000", "ta": 22.6},
]


class WeatherTests(unittest.TestCase):
    def test_ultima_observacion_con_temperatura(self):
        self.assertEqual(
            weather.latest_temperature(OBS),
            {"temp": 23, "time": "2026-10-02T15:00:00+0000"},
        )
        self.assertIsNone(weather.latest_temperature({"no": "lista"}))

    def test_sigue_el_enlace_de_datos_y_envia_la_clave(self):
        calls = []

        def get_json(url, api_key=""):
            calls.append((url, api_key))
            if url == weather.OBSERVATION_URL:
                return {"estado": 200, "datos": "https://opendata.aemet.es/opendata/sh/abc"}
            return OBS

        data = weather.current_weather("CLAVE", get_json)
        self.assertEqual(data["temp"], 23)
        self.assertEqual(data["source"], "AEMET")
        self.assertEqual(calls[0], (weather.OBSERVATION_URL, "CLAVE"))
        self.assertEqual(calls[1][1], "")  # el enlace de datos no lleva la clave

    def test_sin_clave_no_llama_a_aemet(self):
        def get_json(*_):
            raise AssertionError("no debería llamar")

        self.assertIsNone(weather.current_weather("", get_json)["temp"])

    def test_si_aemet_falla_devuelve_sin_temperatura(self):
        def get_json(*_):
            raise OSError("caído")

        self.assertIsNone(weather.current_weather("CLAVE", get_json)["temp"])

    def test_clave_caducada_se_avisa(self):
        import urllib.error

        def get_json(url, api_key=""):
            raise urllib.error.HTTPError(url, 401, "Unauthorized", {}, None)

        data = weather.current_weather("VIEJA", get_json)
        self.assertIsNone(data["temp"])
        self.assertEqual(data["error"], "clave")

    def test_cache_del_servidor_corta_si_fallo(self):
        os.environ.setdefault("MONGODB_URI", "")
        import server

        server._weather_cache.clear()
        server.get_weather_payload(lambda: {"temp": None})
        self.assertLess(server._weather_cache["now"][0] - server.time.time(), 11 * 60)
        server._weather_cache.clear()
        server.get_weather_payload(lambda: {"temp": 20})
        self.assertGreater(server._weather_cache["now"][0] - server.time.time(), 25 * 60)
        server._weather_cache.clear()


if __name__ == "__main__":
    unittest.main()
