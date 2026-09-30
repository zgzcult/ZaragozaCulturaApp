"""Pruebas de la recepción de envíos. Ejecutar con:

    python backend/test_submissions.py
"""

import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))

import submissions  # noqa: E402


def body(**overrides):
    data = {"type": "mejora", "title": "Modo oscuro", "description": "Sería genial poder usar la app de noche."}
    data.update(overrides)
    return json.dumps(data).encode("utf-8")


class ValidateTests(unittest.TestCase):
    def test_acepta_un_envio_correcto(self):
        clean, error = submissions.validate(json.loads(body()))
        self.assertIsNone(error)
        self.assertEqual(clean["title"], "Modo oscuro")

    def test_rechaza_tipo_desconocido(self):
        self.assertIsNotNone(submissions.validate({"type": "spam", "title": "abc", "description": "x" * 20})[1])

    def test_rechaza_titulo_o_descripcion_cortos(self):
        self.assertIsNotNone(submissions.validate({"type": "mejora", "title": "a", "description": "x" * 20})[1])
        self.assertIsNotNone(submissions.validate({"type": "mejora", "title": "abc", "description": "corta"})[1])

    def test_recorta_y_limpia(self):
        clean, _ = submissions.validate(
            {"type": "mejora", "title": "T" * 500, "description": "d\x00esc" + "x" * 5000, "contact": "  a@b.es "}
        )
        self.assertEqual(len(clean["title"]), submissions.MAX_TITLE)
        self.assertLessEqual(len(clean["description"]), submissions.MAX_DESCRIPTION)
        self.assertNotIn("\x00", clean["description"])
        self.assertEqual(clean["contact"], "a@b.es")

    def test_no_es_un_diccionario(self):
        self.assertIsNotNone(submissions.validate([1, 2])[1])


class EmailTests(unittest.TestCase):
    def test_asunto_mejora(self):
        clean = {"type": "mejora", "title": "Modo oscuro", "description": "Texto de prueba largo", "contact": ""}
        subject, text = submissions.build_email(clean)
        self.assertEqual(subject, "Mejora")
        self.assertIn("Modo oscuro", text)
        self.assertNotIn("Contacto", text)

    def test_incluye_contacto(self):
        clean = {"type": "evento", "title": "Concierto", "description": "Texto de prueba largo", "contact": "yo@ejemplo.es"}
        subject, text = submissions.build_email(clean)
        self.assertEqual(subject, "Evento")
        self.assertIn("Contacto: yo@ejemplo.es", text)

    def test_sin_configurar_no_envia(self):
        old = {k: os.environ.pop(k, None) for k in ("RESEND_API_KEY", "NOTIFY_EMAIL")}
        try:
            self.assertFalse(submissions.send_email_resend("Mejora", "texto"))
        finally:
            for key, value in old.items():
                if value is not None:
                    os.environ[key] = value


class RateLimiterTests(unittest.TestCase):
    def test_limita_por_ip_y_ventana(self):
        limiter = submissions.RateLimiter(limit=2, window=100)
        self.assertTrue(limiter.allow("1.1.1.1", now=0))
        self.assertTrue(limiter.allow("1.1.1.1", now=1))
        self.assertFalse(limiter.allow("1.1.1.1", now=2))
        self.assertTrue(limiter.allow("2.2.2.2", now=2))  # otra IP
        self.assertTrue(limiter.allow("1.1.1.1", now=101))  # ventana pasada


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.stored = []
        self.sent = []
        self.limiter = submissions.RateLimiter()

    def run_process(self, raw, *, store_ok=True, send_ok=True, ip="9.9.9.9"):
        def store(doc):
            self.stored.append(doc)
            return store_ok

        def send(subject, text, reply_to):
            self.sent.append((subject, text, reply_to))
            return send_ok

        return submissions.process_submission(raw, ip, limiter=self.limiter, store=store, send=send)

    def test_guarda_y_envia(self):
        status, response = self.run_process(body(contact="yo@ejemplo.es"))
        self.assertEqual((status, response), (200, {"ok": True}))
        self.assertEqual(self.sent[0][0], "Mejora")
        self.assertEqual(self.sent[0][2], "yo@ejemplo.es")  # reply_to
        self.assertIn("createdAt", self.stored[0])

    def test_contacto_que_no_es_correo_no_va_como_reply_to(self):
        self.run_process(body(contact="600 123 456"))
        self.assertIsNone(self.sent[0][2])

    def test_si_falla_el_correo_pero_se_guarda_es_correcto(self):
        self.assertEqual(self.run_process(body(), send_ok=False)[0], 200)

    def test_si_falla_todo_devuelve_503(self):
        self.assertEqual(self.run_process(body(), store_ok=False, send_ok=False)[0], 503)

    def test_json_invalido_y_datos_invalidos(self):
        self.assertEqual(self.run_process(b"no es json")[0], 400)
        self.assertEqual(self.run_process(body(title="a"))[0], 422)
        self.assertEqual(self.stored, [])

    def test_demasiado_grande(self):
        self.assertEqual(self.run_process(b"x" * (submissions.MAX_BODY_BYTES + 1))[0], 413)

    def test_limite_de_envios(self):
        for _ in range(submissions.RATE_LIMIT):
            self.assertEqual(self.run_process(body())[0], 200)
        self.assertEqual(self.run_process(body())[0], 429)


class ServerTests(unittest.TestCase):
    """El servidor real acepta POST /submit y rechaza otras rutas."""

    @classmethod
    def setUpClass(cls):
        os.environ.pop("MONGODB_URI", None)
        os.environ.pop("RESEND_API_KEY", None)
        import server

        cls.server = server.ThreadingHTTPServer(("127.0.0.1", 0), server.EventHandler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def post(self, path, data):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}", data=data, headers={"Content-Type": "application/json"}, method="POST"
        )
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def test_ruta_desconocida(self):
        self.assertEqual(self.post("/otra", b"{}")[0], 404)

    def test_sin_configuracion_devuelve_503(self):
        # Sin base de datos ni correo configurados no hay dónde registrar el envío.
        status, response = self.post("/submit", body())
        self.assertEqual(status, 503)
        self.assertFalse(response["ok"])

    def test_envio_invalido(self):
        self.assertEqual(self.post("/submit", body(title="a"))[0], 422)


if __name__ == "__main__":
    unittest.main()
