"""Pruebas de los informes de errores y de la página de enlace. Ejecutar con:

    python backend/test_crashes.py
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crashes  # noqa: E402
import event_links  # noqa: E402
import submissions  # noqa: E402

REPORT = {
    "error": "Null check operator used on a null value",
    "stack": "#0 _HomeScreenState.build (package:app/home.dart:120:14)\n#1 StatefulElement.build (framework.dart:5800)",
    "appVersion": "1.0.0+1",
    "platform": "android",
    "osVersion": "14",
}


def body(**overrides):
    return json.dumps({**REPORT, **overrides}).encode("utf-8")


class CrashTests(unittest.TestCase):
    def run_report(self, raw, first_time=True, limiter=None):
        stored, sent = [], []

        def store(report):
            stored.append(report)
            return first_time

        def send(subject, text, reply_to):
            sent.append((subject, text))
            return True

        status, _ = crashes.process_report(
            raw, "1.2.3.4", limiter=limiter or submissions.RateLimiter(limit=20), store=store, send=send
        )
        return status, stored, sent

    def test_un_error_nuevo_se_guarda_y_avisa_por_correo(self):
        status, stored, sent = self.run_report(body())
        self.assertEqual(status, 200)
        self.assertEqual(stored[0]["appVersion"], "1.0.0+1")
        self.assertEqual(sent[0][0], "Error en la app")
        self.assertIn("Null check operator", sent[0][1])
        self.assertIn("home.dart", sent[0][1])

    def test_un_error_repetido_no_manda_otro_correo(self):
        status, stored, sent = self.run_report(body(), first_time=False)
        self.assertEqual(status, 200)
        self.assertEqual(len(stored), 1)
        self.assertEqual(sent, [])

    def test_si_no_se_pudo_guardar_se_avisa_igualmente(self):
        _, _, sent = self.run_report(body(), first_time=None)
        self.assertEqual(len(sent), 1)

    def test_misma_huella_aunque_cambien_los_numeros_de_linea(self):
        a = crashes.signature(REPORT["error"], REPORT["stack"])
        b = crashes.signature(REPORT["error"], REPORT["stack"].replace("120:14", "131:9"))
        c = crashes.signature("Otro error", REPORT["stack"])
        self.assertEqual(a, b)
        self.assertNotEqual(a, c)

    def test_solo_datos_tecnicos_y_recortados(self):
        report = crashes.validate({**REPORT, "stack": "x" * 99999, "email": "a@b.c", "deviceId": "123"})
        self.assertEqual(len(report["stack"]), crashes.MAX_STACK)
        self.assertEqual(
            sorted(report), ["appVersion", "error", "osVersion", "platform", "signature", "stack"]
        )

    def test_rechaza_lo_que_no_es_un_informe(self):
        for raw in (b"no json", b"[]", body(error=""), body(error=5)):
            self.assertIn(self.run_report(raw)[0], (400, 422))

    def test_limite_por_ip(self):
        limiter = submissions.RateLimiter(limit=2)
        codes = [self.run_report(body(), limiter=limiter)[0] for _ in range(3)]
        self.assertEqual(codes, [200, 200, 429])

    def test_demasiado_grande(self):
        self.assertEqual(self.run_report(b"x" * (crashes.MAX_BODY_BYTES + 1))[0], 413)


EVENT_ID = "0123456789abcdef0123456789abcdef01234567"
EVENT = {
    "title": 'Concierto "especial" <b>',
    "date": "2026-10-10",
    "time": "20:00",
    "place": "Auditorio",
    "imageUrl": "/cont/paginas/actividades/imagen/x.png",
}


class EventLinkTests(unittest.TestCase):
    def test_pagina_con_la_actividad_y_el_boton_de_la_app(self):
        page = event_links.render_event_page(EVENT_ID, EVENT)
        self.assertIn(f'href="manazaragoza://open/evento/{EVENT_ID}"', page)
        self.assertIn("10 de octubre de 2026 · 20:00", page)
        self.assertIn("Auditorio", page)
        self.assertIn('property="og:image" content="https://www.zaragoza.es/cont/paginas/actividades/imagen/x.png"', page)
        self.assertIn("Muy pronto disponible", page)

    def test_el_titulo_se_escapa(self):
        page = event_links.render_event_page(EVENT_ID, EVENT)
        self.assertNotIn("<b>", page)
        self.assertIn("Concierto &quot;especial&quot; &lt;b&gt;", page)

    def test_actividad_que_ya_no_existe(self):
        page = event_links.render_event_page(EVENT_ID, None)
        self.assertIn("ya no está en la agenda", page)
        self.assertIn("Abrir en la app", page)

    def test_enlace_a_la_tienda_cuando_esta_publicada(self):
        page = event_links.render_event_page(EVENT_ID, EVENT, "https://play.google.com/store/apps/details?id=x")
        self.assertIn("Descárgala gratis", page)

    def test_identificador_no_valido_no_se_cuela_en_el_enlace(self):
        malo = '"><script>alert(1)</script>'
        self.assertFalse(event_links.valid_event_id(malo))
        page = event_links.render_event_page(malo, None)
        self.assertNotIn("<script>alert", page)
        self.assertIsNone(event_links.find_event(malo))

    def test_pagina_de_privacidad_al_dia(self):
        os.environ.setdefault("MONGODB_URI", "")
        import server

        page = server.render_privacy_page()
        self.assertIn("Informes de errores", page)
        self.assertNotIn("Google Formularios", page)
        self.assertIn("7 de octubre de 2026", page)


if __name__ == "__main__":
    unittest.main()
