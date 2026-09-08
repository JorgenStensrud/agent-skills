#!/usr/bin/env python3
"""Tester for trumf-kvitteringer. Kjør: python3 tests/test_trumf_kvitteringer.py

Ingen nettverk, ingen ekte innlogging, ingen ekte kvitteringer. Alle svar er
faste og oppdiktede, formet etter det NorgesGruppen selv dokumenterer.
"""
from __future__ import annotations

import base64
import io
import json
import os
import tempfile
import time
import unittest
import urllib.error
import zipfile
from email.message import Message
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from unittest import mock

BIN = Path(__file__).resolve().parent.parent / "bin" / "trumf-kvitteringer"

_spec = spec_from_loader("tk", SourceFileLoader("tk", str(BIN)))
tk = module_from_spec(_spec)
_spec.loader.exec_module(tk)


# --------------------------------------------------------------------------
# Oppdiktede data. Formen er fra NorgesGruppens egen dokumentasjon av
# utleveringsformatet; verdiene er funnet på.
# --------------------------------------------------------------------------

KJOPSTRANSAKSJONER = [
    {
        "dato": "12.03.2026",
        "kvitteringsnummer": "10001",
        "kjede": None,
        "butikknavn": "KIWI 999 Testveien",
        "totaltBelop": "63.10",
        "korttype": "ZTLD",
        "kanal": None,
        "varelinjer": [
            {"varenavn": "TESTMELK 1L", "vareAntallVekt": "2.000", "vareBelop": "41.60"},
            {"varenavn": "TESTBRØD", "vareAntallVekt": "1.000", "vareBelop": "21.50"},
        ],
    },
]

BONUSTRANSAKSJONER = [
    {
        "forretningspartnerNummer": None,
        "forretningspartnerNavn": None,
        "historikkPerKanalListe": [],
        "salgshistorikkForKanal": [
            {"butikknavn": "Testbonus", "dato": "12.03.2026",
             "belop": "63.10", "bonus": "0.63"},
        ],
    },
]

STATUS_KLAR = {
    "OrderTime": "2026-03-16T22:54:28",
    "OrderExpiration": "2026-04-15",
    "Period": "Siste 3 år",
    "WantsSalesHistory": True,
    "WantsSalesHistoryPerTrade": True,
    "OrderActive": True,
    "OrderReady": True,
}

STATUS_UNDERVEIS = {**STATUS_KLAR, "OrderReady": False}
STATUS_INGEN = {**STATUS_KLAR, "OrderReady": False, "OrderActive": False}


def b64(obj) -> str:
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def lag_token(*, utloper_om=3600, medlem="87654321") -> str:
    return ".".join([
        b64({"alg": "none", "typ": "JWT"}),
        b64({"exp": int(time.time()) + utloper_om, tk.MEDLEM_CLAIM: medlem}),
        "signatur",
    ])


# --------------------------------------------------------------------------
# Falsk HTTP. Vi bytter ut åpneren, ikke koden under test.
# --------------------------------------------------------------------------

class FakeSvar:
    def __init__(self, status, body, headers=None):
        self.status = status
        self._body = body if isinstance(body, bytes) else body.encode()
        self.headers = Message()
        for navn, verdi in (headers or {}).items():
            self.headers[navn] = verdi

    def read(self):
        return self._body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def http_feil(url, kode, headers=None, body=b""):
    hdrs = Message()
    for navn, verdi in (headers or {}).items():
        hdrs[navn] = verdi
    return urllib.error.HTTPError(url, kode, "feil", hdrs, io.BytesIO(body))


class FakeOpener:
    """Ruter på (metode, url-prefiks). Registrerer alt som ble sendt."""

    def __init__(self, ruter):
        self.ruter = ruter
        self.kall = []

    def open(self, req, timeout=None):
        url = req.full_url
        self.kall.append({
            "metode": req.get_method(),
            "url": url,
            "headers": {k.lower(): v for k, v in req.headers.items()},
            "body": json.loads(req.data) if req.data else None,
        })
        for prefiks, svar in self.ruter.items():
            if url.startswith(prefiks):
                resultat = svar(req) if callable(svar) else svar
                if isinstance(resultat, urllib.error.HTTPError):
                    raise resultat
                return resultat
        raise AssertionError(f"ingen rute for {url}")


class NettverksTest(unittest.TestCase):
    """Felles rigg: temp-mapper for config og data, falsk åpner."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        rot = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {
            "TRUMF_KVITTERINGER_CONFIG_DIR": str(rot / "config"),
            "TRUMF_KVITTERINGER_DATA_DIR": str(rot / "data"),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.addCleanup(self.tmp.cleanup)

    def client(self, ruter, *, cookies=None, token=None, medlem=None):
        opener = FakeOpener(ruter)
        with mock.patch("urllib.request.build_opener", return_value=opener):
            c = tk.Client()
        c.cookies = dict(cookies or {"sesjon": "abc"})
        c.token = token
        c.medlem_id = medlem
        c.opener = opener
        return c

    def lagre_sesjon(self, token=None, medlem="87654321"):
        tk.write_private(tk.Client.session_path(), json.dumps({
            "cookies": {"sesjon": "abc", "idsrv": "def"},
            "token": token or lag_token(medlem=medlem),
            "medlem_id": medlem,
        }))


# --------------------------------------------------------------------------
# Informasjonskapsler fra utklippstavlen
# --------------------------------------------------------------------------

class TestCookieInput(unittest.TestCase):
    def test_raa_header(self):
        self.assertEqual(tk.parse_cookie_input("a=1; b=2"), {"a": "1", "b": "2"})

    def test_med_cookie_prefiks(self):
        self.assertEqual(tk.parse_cookie_input("Cookie: a=1; b=2"),
                         {"a": "1", "b": "2"})

    def test_copy_as_curl(self):
        curl = (
            "curl 'https://www.trumf.no/profil' \\\n"
            "  -H 'accept: text/html' \\\n"
            "  -H 'cookie: session-token=xyz; idsrv=abc' \\\n"
            "  -H 'user-agent: Mozilla/5.0'"
        )
        self.assertEqual(tk.parse_cookie_input(curl),
                         {"session-token": "xyz", "idsrv": "abc"})

    def test_curl_med_b_flagg(self):
        self.assertEqual(
            tk.parse_cookie_input("curl 'https://www.trumf.no' -b 'a=1; b=2'"),
            {"a": "1", "b": "2"})

    def test_verdier_med_likhetstegn_beholdes(self):
        # JWT-lignende kapselverdier ender ofte på '='.
        self.assertEqual(tk.parse_cookie_input("t=abc=="), {"t": "abc=="})

    def test_tomt_gir_tomt(self):
        self.assertEqual(tk.parse_cookie_input("   "), {})
        self.assertEqual(tk.parse_cookie_input("bare-tull"), {})


# --------------------------------------------------------------------------
# Token
# --------------------------------------------------------------------------

class TestToken(unittest.TestCase):
    def test_medlem_fra_claim(self):
        self.assertEqual(tk.medlem_fra_token(lag_token(medlem="11223344")),
                         "11223344")

    def test_utloper_leses(self):
        token = lag_token(utloper_om=600)
        self.assertAlmostEqual(tk.token_utloper(token), time.time() + 600, delta=5)

    def test_soppel_gir_none(self):
        self.assertIsNone(tk.medlem_fra_token("ikke-et-token"))
        self.assertIsNone(tk.token_utloper("ikke-et-token"))

    def test_medlemsnummer_maskeres(self):
        self.assertEqual(tk.maskert("87654321"), "…4321")


# --------------------------------------------------------------------------
# Fornying
# --------------------------------------------------------------------------

class TestFornying(NettverksTest):
    def test_ferskt_token_gjenbrukes_uten_kall(self):
        token = lag_token(utloper_om=3600)
        c = self.client({}, token=token)
        self.assertEqual(c.ensure_token(), token)
        self.assertEqual(c.opener.kall, [])

    def test_utloept_token_fornyes_med_kapsler(self):
        nytt = lag_token(utloper_om=3600)
        c = self.client(
            {f"{tk.TRUMF}/api/auth/getToken": FakeSvar(200, f'"{nytt}"')},
            token=lag_token(utloper_om=-10))
        self.assertEqual(c.ensure_token(), nytt)
        self.assertEqual(c.opener.kall[0]["headers"]["cookie"], "sesjon=abc")

    def test_nye_kapsler_fra_svaret_tas_vare_paa(self):
        nytt = lag_token()
        c = self.client({f"{tk.TRUMF}/api/auth/getToken": FakeSvar(
            200, f'"{nytt}"', {"Set-Cookie": "sesjon=fornyet; Path=/; HttpOnly"})})
        c.ensure_token()
        self.assertEqual(c.cookies["sesjon"], "fornyet")

    def test_gettoken_null_faller_tilbake_til_session(self):
        nytt = lag_token()
        c = self.client({
            f"{tk.TRUMF}/api/auth/getToken": FakeSvar(200, "null"),
            f"{tk.TRUMF}/api/auth/session": FakeSvar(
                200, json.dumps({"accessToken": nytt, "memberId": "87654321"})),
        })
        self.assertEqual(c.ensure_token(), nytt)

    def test_idsrv_reservevei_gir_ny_sesjon(self):
        nytt = lag_token()
        tilstand = {"innlogget": False}

        def gettoken(_req):
            return FakeSvar(200, f'"{nytt}"' if tilstand["innlogget"] else "null")

        def login(_req):
            tilstand["innlogget"] = True
            return FakeSvar(200, "<html>ok</html>",
                            {"Set-Cookie": "sesjon=ny-fra-idsrv; Path=/"})

        c = self.client({
            f"{tk.TRUMF}/api/auth/getToken": gettoken,
            f"{tk.TRUMF}/api/auth/session": FakeSvar(200, "{}"),
            f"{tk.TRUMF}/api/login": login,
        }, cookies={"sesjon": "gammel", "idsrv": "lever"})

        self.assertEqual(c.ensure_token(), nytt)
        self.assertEqual(c.cookies["sesjon"], "ny-fra-idsrv")

    def test_alt_doedt_sier_logg_inn_igjen_og_returnerer_ikke_tomt(self):
        c = self.client({
            f"{tk.TRUMF}/api/auth/getToken": FakeSvar(200, "null"),
            f"{tk.TRUMF}/api/auth/session": FakeSvar(200, "{}"),
            f"{tk.TRUMF}/api/login": lambda req: FakeSvar(302, "", {
                "Location": "https://id.trumf.no/ui/login?x=1"}),
            "https://id.trumf.no/ui/login": FakeSvar(200, "<html>logg inn</html>"),
        }, cookies={"sesjon": "doed", "idsrv": "doed"})

        with self.assertRaises(tk.SessionExpired) as ctx:
            c.ensure_token()
        self.assertIn("oppsett", str(ctx.exception))

    def test_omdirigeringer_samler_kapsler_fra_hvert_hopp(self):
        c = self.client({
            f"{tk.TRUMF}/api/login": http_feil(
                f"{tk.TRUMF}/api/login", 302,
                {"Location": "https://id.trumf.no/connect/authorize",
                 "Set-Cookie": "hopp1=a; Path=/"}),
            "https://id.trumf.no/connect/authorize": http_feil(
                "https://id.trumf.no/connect/authorize", 302,
                {"Location": "https://www.trumf.no/callback",
                 "Set-Cookie": "hopp2=b; Path=/"}),
            f"{tk.TRUMF}/callback": FakeSvar(200, "ok", {"Set-Cookie": "hopp3=c"}),
        }, cookies={"idsrv": "lever"})

        c.request(f"{tk.TRUMF}/api/login", follow=True)
        self.assertEqual(c.cookies["hopp1"], "a")
        self.assertEqual(c.cookies["hopp2"], "b")
        self.assertEqual(c.cookies["hopp3"], "c")


# --------------------------------------------------------------------------
# Bestilling
# --------------------------------------------------------------------------

class TestBestilling(NettverksTest):
    def test_bestiller_json_med_varelinjer(self):
        c = self.client({f"{tk.NGDATA}/innsyn": FakeSvar(201, "")},
                        token=lag_token(), medlem="87654321")
        c.bestill("SISTE_3_AR")

        kall = c.opener.kall[0]
        self.assertEqual(kall["metode"], "POST")
        self.assertEqual(kall["url"], f"{tk.NGDATA}/innsyn")
        self.assertEqual(kall["headers"]["fwc-chain-id"], "133")
        self.assertTrue(kall["headers"]["authorization"].startswith("Bearer eyJ"))
        self.assertEqual(kall["body"], {
            "medlemId": "87654321",
            "onskerProfil": False,
            "onskerDigitalHistorikk": False,
            "onskerDialoghistorikk": False,
            "onskerOrdrehistorikk": False,
            "onskerSalgshistorikk": True,
            "onskerSalgshistorikkPerHandel": True,
            "periode": "SISTE_3_AR",
            "format": "JSON",
        })

    def test_annet_enn_201_er_en_feil_ikke_en_suksess(self):
        c = self.client({f"{tk.NGDATA}/innsyn": FakeSvar(200, "")},
                        token=lag_token(), medlem="87654321")
        with self.assertRaises(tk.ShapeChanged):
            c.bestill("SISTE_3_AR")

    def test_uten_medlemsnummer_stopper_vi(self):
        c = self.client({f"{tk.TRUMF}/api/auth/session": FakeSvar(200, "{}")},
                        token="ikke-et-jwt")
        with self.assertRaises(tk.ShapeChanged):
            c.bestill("SISTE_3_AR")

    def test_status_oversettes(self):
        c = self.client({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_KLAR)),
        }, token=lag_token())
        status = c.hent_bestillingsstatus()
        self.assertTrue(status["klar"])
        self.assertTrue(status["aktiv"])
        self.assertEqual(status["bestilt"], "2026-03-16T22:54:28")
        self.assertIn("isDataportability=true", c.opener.kall[0]["url"])

    def test_status_uten_orderready_er_formendring(self):
        c = self.client({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps({"noe": "annet"})),
        }, token=lag_token())
        with self.assertRaises(tk.ShapeChanged):
            c.hent_bestillingsstatus()


class TestDobbeltbestilling(NettverksTest):
    def _kjor_bestill(self, ruter, argv=("bestill",)):
        opener = FakeOpener(ruter)
        with mock.patch("urllib.request.build_opener", return_value=opener):
            kode = tk.main(list(argv))
        return kode, opener

    def test_aktiv_bestilling_blokkerer(self):
        self.lagre_sesjon()
        kode, opener = self._kjor_bestill({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_UNDERVEIS)),
        })
        self.assertEqual(kode, 3)
        self.assertFalse([k for k in opener.kall if k["metode"] == "POST"])

    def test_klar_men_uhentet_bestilling_blokkerer_ogsaa(self):
        self.lagre_sesjon()
        kode, opener = self._kjor_bestill({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_KLAR)),
        })
        self.assertEqual(kode, 3)
        self.assertFalse([k for k in opener.kall if k["metode"] == "POST"])

    def test_paa_nytt_overstyrer(self):
        self.lagre_sesjon()
        kode, opener = self._kjor_bestill({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_KLAR)),
            f"{tk.NGDATA}/innsyn": FakeSvar(201, ""),
        }, argv=("bestill", "--paa-nytt"))
        self.assertEqual(kode, 0)
        self.assertTrue([k for k in opener.kall if k["metode"] == "POST"])

    def test_ingen_aktiv_bestilling_slipper_gjennom_og_noteres(self):
        self.lagre_sesjon()
        kode, opener = self._kjor_bestill({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_INGEN)),
            f"{tk.NGDATA}/innsyn": FakeSvar(201, ""),
        })
        self.assertEqual(kode, 0)
        notat = tk.les_bestilling()
        self.assertEqual(notat["periode"], "SISTE_3_AR")
        self.assertEqual(notat["format"], "JSON")
        self.assertTrue(notat["varelinjer"])

    def test_notat_blokkerer_naar_statuskallet_feiler(self):
        """Klarer vi ikke spørre Trumf, bestiller vi ikke i blinde."""
        self.lagre_sesjon()
        tk.skriv_bestilling({"bestilt": tk.now_iso(), "periode": "SISTE_3_AR"})
        with mock.patch.object(tk.time, "sleep"):   # ingen ekte backoff i test
            kode, opener = self._kjor_bestill({
                f"{tk.TRUMF}/api/common/orderinsight/getstatus": http_feil(
                    f"{tk.TRUMF}/api/common/orderinsight/getstatus", 500),
            })
        self.assertEqual(kode, 3)
        self.assertFalse([k for k in opener.kall if k["metode"] == "POST"])


class TestHent(NettverksTest):
    def _zip(self) -> bytes:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("bonustransaksjoner.json", json.dumps(BONUSTRANSAKSJONER))
            zf.writestr("kjopstransaksjoner_per_handel_per_vare.json",
                        json.dumps(KJOPSTRANSAKSJONER))
        return buf.getvalue()

    def test_ikke_klar_gir_ingen_nedlasting(self):
        self.lagre_sesjon()
        opener = FakeOpener({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_UNDERVEIS)),
        })
        with mock.patch("urllib.request.build_opener", return_value=opener):
            self.assertEqual(tk.main(["hent"]), 3)
        self.assertFalse([k for k in opener.kall if "getfiles" in k["url"]])

    def test_klar_lastes_ned_og_importeres(self):
        self.lagre_sesjon()
        opener = FakeOpener({
            f"{tk.TRUMF}/api/common/orderinsight/getstatus":
                FakeSvar(200, json.dumps(STATUS_KLAR)),
            f"{tk.TRUMF}/api/common/orderinsight/getfiles":
                FakeSvar(200, self._zip(), {"Content-Type": "application/zip"}),
        })
        with mock.patch("urllib.request.build_opener", return_value=opener):
            self.assertEqual(tk.main(["hent"]), 0)

        lagret = list(tk.receipts_dir().glob("*.json"))
        self.assertEqual(len(lagret), 1)
        kvittering = json.loads(lagret[0].read_text(encoding="utf-8"))
        self.assertEqual(kvittering["totalbelop"], 63.10)
        self.assertEqual(len(kvittering["varelinjer"]), 2)

        dumper = list(tk.dumps_dir().glob("*.zip"))
        self.assertEqual(len(dumper), 1)
        self.assertEqual(dumper[0].stat().st_mode & 0o777, 0o600)

    def test_html_i_stedet_for_fil_er_utloept_sesjon(self):
        self.lagre_sesjon()
        c = self.client({
            f"{tk.TRUMF}/api/common/orderinsight/getfiles": FakeSvar(
                200, "<!doctype html><html>logg inn</html>" + " " * 200,
                {"Content-Type": "text/html"}),
        }, token=lag_token())
        with self.assertRaises(tk.SessionExpired):
            c.last_ned()

    def test_tom_fil_er_en_feil_ikke_en_tom_dump(self):
        c = self.client({
            f"{tk.TRUMF}/api/common/orderinsight/getfiles": FakeSvar(200, b""),
        }, token=lag_token())
        with self.assertRaises(tk.ShapeChanged):
            c.last_ned()


# --------------------------------------------------------------------------
# Parseren skal fortsatt virke helt uten innlogging
# --------------------------------------------------------------------------

class TestParserUtenInnlogging(NettverksTest):
    def test_importerer_dokumentert_utleveringsformat(self):
        fil = Path(self.tmp.name) / "dump.json"
        fil.write_text(json.dumps(KJOPSTRANSAKSJONER), encoding="utf-8")

        self.assertEqual(tk.main(["importer", str(fil)]), 0)
        self.assertFalse(tk.Client.session_path().exists())

        kvitteringer = tk.les_kvitteringer()
        self.assertEqual(len(kvitteringer), 1)
        kv = kvitteringer[0]
        self.assertEqual(kv["dato"], "2026-03-12")
        self.assertEqual(kv["kvitteringsnummer"], "10001")
        self.assertEqual(kv["butikknavn"], "KIWI 999 Testveien")
        self.assertEqual(kv["totalbelop"], 63.10)
        self.assertEqual(kv["varelinjer"][0]["antall"], 2.0)
        self.assertEqual(kv["varelinjer"][0]["belop"], 41.60)
        self.assertNotIn("advarsel_sum", kv["_meta"])

    def test_zip_med_bonus_og_kjop_finner_kvitteringene(self):
        fil = Path(self.tmp.name) / "utlevering.zip"
        with zipfile.ZipFile(fil, "w") as zf:
            zf.writestr("bonustransaksjoner.json", json.dumps(BONUSTRANSAKSJONER))
            zf.writestr("kjopstransaksjoner_per_handel_per_vare.json",
                        json.dumps(KJOPSTRANSAKSJONER))
        self.assertEqual(tk.main(["importer", str(fil)]), 0)
        self.assertEqual(len(tk.les_kvitteringer()), 1)

    def test_import_er_idempotent(self):
        fil = Path(self.tmp.name) / "dump.json"
        fil.write_text(json.dumps(KJOPSTRANSAKSJONER), encoding="utf-8")
        tk.main(["importer", str(fil)])
        tk.main(["importer", str(fil)])
        self.assertEqual(len(tk.les_kvitteringer()), 1)

    def test_ukjent_format_feiler_hoeylytt(self):
        fil = Path(self.tmp.name) / "rart.json"
        fil.write_text(json.dumps({"noe": "helt annet"}), encoding="utf-8")
        with self.assertRaises(tk.TrumfError):
            tk.importer_fil(fil)

    def test_kommandoer_uten_sesjon_ber_om_oppsett(self):
        self.assertEqual(tk.main(["bestilling"]), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
