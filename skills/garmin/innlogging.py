#!/usr/bin/env python3
"""Engangs innloggingsside for Garmin, for når brukeren sitter på telefonen.

Et passord skal ikke gjennom en chat — det blir liggende i loggen for alltid. Denne
serverer et lite skjema på tailnettet i stedet: brukeren fyller inn e-post, passord
og engangskoden, tokens lagres, og serveren slår seg av. Passordet ligger i minnet
til forespørselen er ferdig og skrives aldri noe sted.

    python3 innlogging.py [--port 8477]

Krever HTTPS utenfra: `tailscale serve --bg --https <port> http://127.0.0.1:<port>`.
Over ren HTTP sender telefonen passordet i klartekst over nettet.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKENS = os.path.expanduser(os.environ.get("GARMIN_TOKENS", "~/.garminconnect"))

SIDE = """<!doctype html><html lang="no"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Logg inn på Garmin</title>
<style>
 body {{ margin:0; padding:2.5rem 1.5rem; font:1rem/1.5 -apple-system,system-ui,sans-serif;
        background:#f4f1ec; color:#1f2d3d; }}
 form {{ max-width:26rem; }} h1 {{ font-size:1.5rem; margin:0 0 .5rem; }}
 p {{ margin:0 0 1.25rem; color:#5a6b7b; }}
 label {{ display:block; font-weight:600; margin:1rem 0 .35rem; }}
 input {{ width:100%; box-sizing:border-box; padding:.8rem; font-size:1rem;
          border:1px solid #cfc8bd; border-radius:10px; background:#fff; }}
 button {{ margin-top:1.5rem; width:100%; padding:.9rem; font-size:1rem; font-weight:600;
           color:#fff; background:#c0392b; border:0; border-radius:999px; }}
 .melding {{ padding:.9rem 1rem; border-radius:10px; margin-bottom:1rem; }}
 .feil {{ background:#fae3df; color:#8c2d20; }} .ok {{ background:#e2efe4; color:#24613a; }}
</style>
<form method="post"><h1>{tittel}</h1><p>{under}</p>{melding}{felt}
<button type="submit">{knapp}</button></form></html>"""


def side(tittel, under, felt, knapp, melding="", slag="feil"):
    m = f'<div class="melding {slag}">{html.escape(melding)}</div>' if melding else ""
    return SIDE.format(tittel=tittel, under=under, felt=felt, knapp=knapp, melding=m).encode()


FELT_LOGIN = """
 <label for="e">E-post</label>
 <input id="e" name="epost" type="email" autocomplete="username" required autocapitalize="off">
 <label for="p">Passord</label>
 <input id="p" name="passord" type="password" autocomplete="current-password" required>
"""
FELT_MFA = """
 <label for="k">Engangskoden fra Garmin</label>
 <input id="k" name="kode" inputmode="numeric" autocomplete="one-time-code" required autofocus>
"""


class Tilstand:
    """Det som må overleve mellom passord-steget og kode-steget."""

    def __init__(self):
        self.klient = None
        self.mellomsteg = None
        self.ferdig = threading.Event()
        self.resultat = "avbrutt"


def lagre(klient) -> None:
    os.makedirs(TOKENS, mode=0o700, exist_ok=True)
    klient.client.dump(TOKENS)
    os.chmod(TOKENS, 0o700)


def lag_handler(t: Tilstand):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):  # ikke logg noe; forespørselen bærer et passord
            pass

        def svar(self, kropp: bytes, kode: int = 200):
            self.send_response(kode)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(kropp)))
            self.end_headers()
            self.wfile.write(kropp)

        def do_GET(self):
            if t.mellomsteg:
                self.svar(side("Engangskode", "Garmin har sendt deg en kode.", FELT_MFA, "Fullfør"))
            else:
                self.svar(side("Logg inn på Garmin", "Går rett til Garmin. Passordet lagres ikke.", FELT_LOGIN, "Logg inn"))

        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            felt = urllib.parse.parse_qs(self.rfile.read(n).decode())
            from garminconnect import Garmin

            if t.mellomsteg:
                kode = (felt.get("kode") or [""])[0].strip()
                try:
                    t.klient.resume_login(t.mellomsteg, kode)
                except Exception as e:  # noqa: BLE001
                    self.svar(side("Engangskode", "Koden ble ikke godtatt.", FELT_MFA, "Prøv igjen", f"{type(e).__name__}: {e}"))
                    return
                try:
                    lagre(t.klient)
                except Exception as e:  # noqa: BLE001
                    self.svar(side("Nesten", "Innlogget, men nøklene lot seg ikke lagre.", "", "", f"{type(e).__name__}: {e}"))
                    return
                self.svar(side("Ferdig", "Du er logget inn. Siden kan lukkes.", "", "", "Tokens lagret.", "ok"))
                t.resultat = "innlogget"
                threading.Timer(1.0, t.ferdig.set).start()
                return

            epost = (felt.get("epost") or [""])[0].strip()
            passord = (felt.get("passord") or [""])[0]
            if not epost or not passord:
                self.svar(side("Logg inn på Garmin", "Begge felt må fylles ut.", FELT_LOGIN, "Logg inn", "Mangler e-post eller passord"))
                return
            klient = Garmin(email=epost, password=passord, return_on_mfa=True)
            del passord
            try:
                status, mellom = klient.login()
            except Exception as e:  # noqa: BLE001
                # 429 er Garmin som strupet IP-en, ikke feil passord. Sier vi ikke
                # det, prøver folk passordet om igjen og gjør ventetiden lengre.
                if "429" in str(e) or "TooManyRequests" in type(e).__name__:
                    self.svar(side("Vent litt", "Garmin har midlertidig stengt for innlogging fra denne maskinen.",
                                   "", "", "For mange forsøk (429). Vent en time og prøv igjen — passordet er ikke problemet.", "feil"))
                    return
                self.svar(side("Logg inn på Garmin", "Garmin avviste innloggingen.", FELT_LOGIN, "Prøv igjen", f"{type(e).__name__}: {e}"))
                return
            # login() svarer («needs_mfa», mellomsteg) når koden trengs, og
            # (None, None) når den gikk rett gjennom. None er altså suksess, ikke
            # feil — å behandle det som feil avviser en innlogging som virket.
            if status == "needs_mfa":
                t.klient, t.mellomsteg = klient, mellom
                self.svar(side("Engangskode", "Garmin har sendt deg en kode.", FELT_MFA, "Fullfør"))
                return
            try:
                lagre(klient)
            except Exception as e:  # noqa: BLE001
                self.svar(side("Nesten", "Innlogget, men nøklene lot seg ikke lagre.", "", "", f"{type(e).__name__}: {e}"))
                return
            self.svar(side("Ferdig", "Du er logget inn. Siden kan lukkes.", "", "", "Tokens lagret.", "ok"))
            t.resultat = "innlogget"
            threading.Timer(1.0, t.ferdig.set).start()

    return H


def main() -> None:
    p = argparse.ArgumentParser(description="Engangs innloggingsside for Garmin.")
    p.add_argument("--port", type=int, default=8477)
    p.add_argument("--minutter", type=int, default=20, help="gi opp etter så lenge")
    args = p.parse_args()

    t = Tilstand()
    tjener = HTTPServer(("127.0.0.1", args.port), lag_handler(t))
    threading.Thread(target=tjener.serve_forever, daemon=True).start()
    print(f"lytter på http://127.0.0.1:{args.port} — legg HTTPS foran med tailscale serve", flush=True)
    t.ferdig.wait(timeout=args.minutter * 60)
    tjener.shutdown()
    print(t.resultat)
    sys.exit(0 if t.resultat == "innlogget" else 2)


if __name__ == "__main__":
    main()
