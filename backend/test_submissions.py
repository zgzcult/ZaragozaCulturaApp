"""Pruebas de la recepción de envíos. Ejecutar con:

    python backend/test_submissions.py
"""

import contextlib
import io
import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request
from unittest import mock

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

    def test_si_resend_rechaza_se_registra_el_motivo(self):
        error = urllib.error.HTTPError(
            "https://api.resend.com/emails",
            403,
            "Forbidden",
            {},
            io.BytesIO(b'{"message":"You can only send testing emails to your own email address"}'),
        )
        env = {"RESEND_API_KEY": "re_clave_de_prueba", "NOTIFY_EMAIL": "yo@ejemplo.es"}
        log = io.StringIO()
        with mock.patch.dict(os.environ, env), mock.patch("urllib.request.urlopen", side_effect=error):
            with contextlib.redirect_stdout(log):
                result = submissions.send_email_resend("Mejora", "texto")
        self.assertFalse(result)
        self.assertIn("403", log.getvalue())
        self.assertIn("your own email address", log.getvalue())
        self.assertNotIn("re_clave_de_prueba", log.getvalue())  # la clave no se escribe en los registros

    def test_sin_configurar_indica_que_variable_falta(self):
        log = io.StringIO()
        with mock.patch.dict(os.environ, {"RESEND_API_KEY": "", "NOTIFY_EMAIL": ""}):
            with contextlib.redirect_stdout(log):
                self.assertFalse(submissions.send_email_resend("Mejora", "texto"))
        self.assertIn("RESEND_API_KEY", log.getvalue())
        self.assertIn("NOTIFY_EMAIL", log.getvalue())

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
        self.attachments = []
        self.limiter = submissions.RateLimiter()

    def run_process(self, raw, *, store_ok=True, send_ok=True, ip="9.9.9.9"):
        def store(doc):
            self.stored.append(doc)
            return store_ok

        def send(subject, text, reply_to, attachments=None):
            self.sent.append((subject, text, reply_to))
            self.attachments.append(attachments)
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


JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 2000
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 2000


def event_body(photo_bytes=None, **overrides):
    import base64

    data = {
        "type": "evento",
        "title": "Concierto solidario",
        "description": "Fecha: 12 de noviembre de 2026\nLugar: Sala Oasis\n\nMúsica en directo.",
        "contact": "hola@example.org",
    }
    if photo_bytes is not None:
        data["photo"] = {"name": "cartel.jpg", "data": base64.b64encode(photo_bytes).decode("ascii")}
    data.update(overrides)
    return json.dumps(data).encode("utf-8")


class PhotoTests(ProcessTests):
    """Foto opcional de «Envía tu evento»."""

    def test_la_foto_llega_adjunta_al_correo_y_no_se_guarda(self):
        import base64

        status, _ = self.run_process(event_body(JPEG))
        self.assertEqual(status, 200)
        self.assertEqual(self.sent[0][0], "Evento")
        self.assertIn("Foto: adjunta", self.sent[0][1])
        attachment = self.attachments[0][0]
        self.assertEqual(attachment["filename"], "evento.jpg")
        self.assertEqual(base64.b64decode(attachment["content"]), JPEG)
        # En la base de datos solo queda constancia de que había foto.
        self.assertTrue(self.stored[0]["hasPhoto"])
        self.assertNotIn("photo", self.stored[0])

    def test_png_tambien_vale_y_el_nombre_lo_pone_el_servidor(self):
        self.run_process(event_body(PNG))
        self.assertEqual(self.attachments[0][0]["filename"], "evento.png")

    def test_sin_foto_el_correo_va_sin_adjuntos(self):
        self.assertEqual(self.run_process(event_body())[0], 200)
        self.assertIsNone(self.attachments[0])
        self.assertFalse(self.stored[0]["hasPhoto"])
        self.assertNotIn("Foto:", self.sent[0][1])

    def test_un_pdf_u_otro_archivo_se_rechaza(self):
        for fake in (b"%PDF-1.7 " + b"x" * 500, b"MZ" + b"x" * 500, b"<html>"):
            status, response = self.run_process(event_body(fake))
            self.assertEqual(status, 422)
            self.assertIn("JPG o PNG", response["error"])
        self.assertEqual(self.sent, [])

    def test_base64_roto(self):
        raw = event_body(photo={"name": "x.jpg", "data": "esto no es base64 !!"})
        self.assertEqual(self.run_process(raw)[0], 422)

    def test_foto_demasiado_grande(self):
        big = b"\xff\xd8\xff" + b"\x00" * submissions.MAX_PHOTO_BYTES
        status, response = self.run_process(event_body(big))
        self.assertIn(status, (413, 422))
        self.assertEqual(self.sent, [])

    def test_las_sugerencias_no_admiten_foto(self):
        self.assertEqual(self.run_process(event_body(JPEG, type="mejora"))[0], 422)

    def test_el_texto_mantiene_su_limite_aunque_haya_foto(self):
        raw = event_body(JPEG, relleno="x" * (submissions.MAX_BODY_BYTES + 10))
        self.assertEqual(self.run_process(raw)[0], 413)

    def test_resend_recibe_los_adjuntos(self):
        captured = {}

        class Response:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def fake_urlopen(request, timeout=0, context=None):
            captured.update(json.loads(request.data.decode("utf-8")))
            return Response()

        original, env = submissions.urllib.request.urlopen, dict(os.environ)
        os.environ.update({"RESEND_API_KEY": "clave-de-prueba", "NOTIFY_EMAIL": "destino@example.org"})
        submissions.urllib.request.urlopen = fake_urlopen
        try:
            ok = submissions.send_email_resend("Evento", "texto", None, [{"filename": "evento.jpg", "content": "QUJD"}])
        finally:
            submissions.urllib.request.urlopen = original
            os.environ.clear()
            os.environ.update(env)
        self.assertTrue(ok)
        self.assertEqual(captured["attachments"], [{"filename": "evento.jpg", "content": "QUJD"}])


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

    def get(self, path):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}") as response:
            return response.status, response.read().decode("utf-8")

    def test_paginas_con_el_nombre_de_la_app(self):
        for path in ("/", "/app", "/privacidad"):
            status, body = self.get(path)
            self.assertEqual(status, 200, path)
            self.assertIn("Maña Zaragoza", body, path)

    def test_ruta_desconocida(self):
        self.assertEqual(self.post("/otra", b"{}")[0], 404)

    def test_sin_configuracion_devuelve_503(self):
        # Sin base de datos ni correo configurados no hay dónde registrar el envío.
        status, response = self.post("/submit", body())
        self.assertEqual(status, 503)
        self.assertFalse(response["ok"])

    def test_envio_invalido(self):
        self.assertEqual(self.post("/submit", body(title="a"))[0], 422)

    def test_el_servidor_real_lee_un_evento_con_foto_de_medio_mega(self):
        photo = b"\xff\xd8\xff\xe0" + os.urandom(500_000)
        raw = event_body(photo)
        self.assertGreater(len(raw), 600_000)
        # Sin correo ni base de datos configurados responde 503: lo importante
        # es que ha leído y validado el envío entero (no 413 ni 400).
        self.assertEqual(self.post("/submit", raw)[0], 503)
        # Y un archivo que no es imagen se rechaza aunque quepa.
        self.assertEqual(self.post("/submit", event_body(b"%PDF-1.7" + os.urandom(1000)))[0], 422)

    def test_el_servidor_real_rechaza_un_envio_enorme(self):
        raw = event_body(b"\xff\xd8\xff" + os.urandom(submissions.MAX_PHOTO_BYTES + 200_000))
        self.assertIn(self.post("/submit", raw)[0], (413, 422))


if __name__ == "__main__":
    unittest.main()
