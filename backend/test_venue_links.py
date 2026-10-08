"""Pruebas del enlace a la página propia de cada acto. Ejecutar con:

    python backend/test_venue_links.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "scraper"))
import venue_links as v  # noqa: E402

BASE = "https://creedencesound.com/agenda_creedence/"
CREEDENCE = {
    "place": "creedence",
    "agenda": "https://creedencesound.com/sala-creedence-conciertos-y-sesiones",
    "events": "/agenda_creedence/",
    "hosts": ["creedence.es"],
}
LINKS = [
    (BASE + "the-sleeveens-usa-en-sala-creedence-zaragoza", ""),
    (BASE + "leyendarian-bcn-spino-zgz-en-sala-creedence-zaragoza", ""),
    (BASE + "the-vee-bees-australia", ""),
    (BASE + "the-darts-usa-2", ""),
    (BASE + "lichis", ""),
]
PLACE = "Sala de Música. Creedence"
FICHA = "https://www.zaragoza.es/sede/servicio/cultura/evento/1"


def event(title, url="http://creedence.es/", place=PLACE):
    return {"title": title, "place": place, "moreInfoUrl": url}


class BestLinkTests(unittest.TestCase):
    def match(self, title, links=LINKS):
        return v.best_link(title, links, v.tokens("creedence"))

    def test_nombre_con_teloneros_y_coletillas(self):
        self.assertEqual(
            self.match("The Sleeveens (USA) - 15 años de Sala Creedence + Los Gurus DJs"),
            BASE + "the-sleeveens-usa-en-sala-creedence-zaragoza",
        )
        self.assertEqual(self.match("The Darts (USA)"), BASE + "the-darts-usa-2")
        self.assertEqual(self.match("The Vee Bees (Australia)"), BASE + "the-vee-bees-australia")

    def test_tolera_una_errata(self):
        self.assertEqual(
            self.match("Leyebdarian (BCN) + Spino (ZGZ) + Manolon DJ"),
            BASE + "leyendarian-bcn-spino-zgz-en-sala-creedence-zaragoza",
        )

    def test_titulo_de_una_sola_palabra(self):
        self.assertEqual(self.match("Lichis"), BASE + "lichis")

    def test_sin_coincidencia_clara_no_devuelve_nada(self):
        self.assertEqual(self.match("Encuentro DJs. de la vieja escuela"), "")
        self.assertEqual(self.match("Swing en plaza con Swing & Co"), "")
        self.assertEqual(self.match("Concierto en la sala"), "")

    def test_dos_palabras_parecidas_no_bastan(self):
        # «familiar» e «historias» se parecen a «familia» e «historia»,
        # pero el acto es otro.
        links = [("https://x.org/p/-minari.-historia-de-mi-familia-zaragoza", "")]
        self.assertEqual(v.best_link("Visita - taller familiar: Historias animadas", links), "")

    def test_una_palabra_suelta_de_la_pagina_no_basta(self):
        links = [("https://x.org/p/naufragios-zaragoza", "")]
        self.assertEqual(v.best_link("Taller- espectáculo: escritura del naufragio", links), "")

    def test_entre_dos_candidatas_gana_la_mas_ajustada(self):
        links = [
            ("https://x.org/p/visita-comentada-a-la-ciencia-de-pixar-para-familias", ""),
            ("https://x.org/p/la-ciencia-de-pixar-zaragoza", "Exposición La ciencia de Pixar"),
        ]
        self.assertEqual(v.best_link("La Ciencia de Pixar", links), "https://x.org/p/la-ciencia-de-pixar-zaragoza")

    def test_dos_candidatas_iguales_es_ambiguo(self):
        links = [("https://x.org/e/the-darts-usa", ""), ("https://x.org/e/the-darts-usa-2", "The Darts USA")]
        self.assertEqual(v.best_link("The Darts (USA)", [links[0], ("https://x.org/e/darts-usa", "")]), "")

    def test_usa_tambien_el_texto_del_enlace(self):
        links = [("https://x.org/p/naufragios-zaragoza", "Exposición Naufragios. Arqueología sumergida")]
        self.assertEqual(v.best_link("Naufragios. Arqueología sumergida", links), links[0][0])


class ResolveTests(unittest.TestCase):
    def test_pagina_del_acto(self):
        self.assertEqual(v.resolve(event("The Darts (USA)"), CREEDENCE, LINKS), BASE + "the-darts-usa-2")

    def test_sin_coincidencia_va_a_la_agenda_del_lugar(self):
        for url in ("http://creedence.es/", FICHA, ""):
            self.assertEqual(v.resolve(event("Swing en plaza", url), CREEDENCE, LINKS), CREEDENCE["agenda"])

    def test_respeta_el_enlace_propio_en_otra_web(self):
        own = "https://entradium.com/es/events/the-darts"
        self.assertEqual(v.resolve(event("The Darts (USA)", own), CREEDENCE, LINKS), own)

    def test_conserva_una_pagina_de_acto_ya_puesta(self):
        own = BASE + "otro-acto-distinto"
        self.assertEqual(v.resolve(event("Swing en plaza", own), CREEDENCE, LINKS), own)

    def test_lugar_sin_paginas_de_actos(self):
        zeta = {"place": "sala zeta", "agenda": "https://www.instagram.com/sala_z_/", "hosts": ["salazeta.com"]}
        self.assertEqual(v.resolve(event("Bonebreaker", "http://www.salazeta.com"), zeta, []), zeta["agenda"])


class ApplyTests(unittest.TestCase):
    def test_solo_toca_los_lugares_apuntados(self):
        events = [
            event("The Darts (USA)"),
            event("Swing en plaza"),
            event("Otra cosa", FICHA, place="Teatro Principal"),
        ]
        exact = v.apply(events, [CREEDENCE], {"creedence": LINKS})
        self.assertEqual(exact, 1)
        self.assertEqual(
            [e["moreInfoUrl"] for e in events],
            [BASE + "the-darts-usa-2", CREEDENCE["agenda"], FICHA],
        )

    def test_sin_lugares_apuntados_no_descarga_nada(self):
        events = [event("Otra cosa", FICHA, place="Teatro Principal")]
        self.assertEqual(v.apply(events, [CREEDENCE], None), 0)
        self.assertEqual(events[0]["moreInfoUrl"], FICHA)

    def test_si_la_agenda_no_se_puede_leer_va_a_la_agenda_general(self):
        def broken(_url):
            raise OSError("caída")

        links = v.collect_links([CREEDENCE], download=broken)
        events = [event("The Darts (USA)")]
        v.apply(events, [CREEDENCE], links)
        self.assertEqual(events[0]["moreInfoUrl"], CREEDENCE["agenda"])


class ExtractTests(unittest.TestCase):
    def test_recoge_solo_las_paginas_de_actos(self):
        page = (
            '<a href="/agenda_creedence/the-darts-usa-2?x=1"><img src="a.jpg"></a>'
            '<a href="/agenda_creedence/the-darts-usa-2">The <b>Darts</b> (USA)</a>'
            '<a href="/quienes-somos">Quiénes somos</a>'
            '<a href="mailto:hola@example.org">Correo</a>'
        )
        links = v.extract_links(page, "https://creedencesound.com/sala", "/agenda_creedence/")
        self.assertEqual(links, [(BASE + "the-darts-usa-2", "The Darts (USA)")])


class ConfigTests(unittest.TestCase):
    def test_la_lista_de_lugares_es_valida(self):
        config = v.load_config()
        self.assertGreaterEqual(len(config), 4)
        for entry in config:
            self.assertEqual(entry["place"], v.plain(entry["place"]), entry["place"])
            self.assertTrue(entry["agenda"].startswith("https://"), entry["place"])
            for page in entry.get("pages", []):
                self.assertTrue(page.startswith("https://"), page)


if __name__ == "__main__":
    unittest.main()
