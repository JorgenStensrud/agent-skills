#!/usr/bin/env python3
"""Pull your own data out of Garmin Connect.

There is no personal API. This drives the same endpoints the phone app uses, via
`garminconnect`, which reverse-engineers them. That is the only route open to an
individual, and it means auth can break when Garmin changes something — it did in
March 2026 and took the whole ecosystem with it. Exit 2 means re-authenticate.

Credentials are never taken as command-line arguments: argv is visible to every
process on the machine. Password comes from a prompt or GARMIN_PASSWORD, and only
the refresh tokens are written to disk.
"""
from __future__ import annotations

import argparse
import datetime as dt
import getpass
import json
import os
import sys

TOKENS = os.path.expanduser(os.environ.get("GARMIN_TOKENS", "~/.garminconnect"))


def feil(kode: int, melding: str) -> None:
    print(f"garmin: {melding}", file=sys.stderr)
    sys.exit(kode)


def klient(krev_innlogget: bool = True):
    try:
        from garminconnect import Garmin
    except ImportError:
        feil(4, "garminconnect mangler — kjør via garmin.sh, som henter den med uvx")
    g = Garmin()
    try:
        g.login(TOKENS)
    except Exception as e:  # noqa: BLE001 — biblioteket kaster mange typer
        if krev_innlogget:
            feil(2, f"ikke innlogget ({type(e).__name__}) — kjør: garmin.sh auth")
        raise
    return g


def auth() -> None:
    from garminconnect import Garmin

    epost = os.environ.get("GARMIN_EMAIL") or input("Garmin-e-post: ").strip()
    passord = os.environ.get("GARMIN_PASSWORD") or getpass.getpass("Passord (vises ikke): ")
    if not epost or not passord:
        feil(3, "trenger både e-post og passord")

    g = Garmin(email=epost, password=passord, prompt_mfa=lambda: input("Engangskode fra Garmin: ").strip())
    try:
        g.login()
    except Exception as e:  # noqa: BLE001
        feil(5, f"innlogging avvist: {type(e).__name__}: {e}")
    os.makedirs(TOKENS, mode=0o700, exist_ok=True)
    g.garth.dump(TOKENS)
    os.chmod(TOKENS, 0o700)
    print(f"innlogget. tokens lagret i {TOKENS}")


def dato(s: str | None, standard_dager: int = 0) -> str:
    if not s or s == "i-dag":
        return (dt.date.today() - dt.timedelta(days=standard_dager)).isoformat()
    if s == "i-gar":
        return (dt.date.today() - dt.timedelta(days=1)).isoformat()
    try:
        return dt.date.fromisoformat(s).isoformat()
    except ValueError:
        feil(3, f"ugyldig dato: {s} (bruk ÅÅÅÅ-MM-DD, «i-dag» eller «i-gar»)")


def skriv(data, tabell: bool) -> None:
    if not tabell:
        print(json.dumps(data, indent=1, ensure_ascii=False, default=str))
        return
    rader = data if isinstance(data, list) else [data]
    if not rader:
        print("(ingenting)")
        return
    if not isinstance(rader[0], dict):
        for r in rader:
            print(r)
        return
    kolonner = list(rader[0].keys())[:6]
    bredder = [max(len(str(k)), *(len(str(r.get(k, ""))[:28]) for r in rader)) for k in kolonner]
    print("  ".join(str(k).ljust(b) for k, b in zip(kolonner, bredder)))
    for r in rader:
        print("  ".join(str(r.get(k, ""))[:28].ljust(b) for k, b in zip(kolonner, bredder)))


# Kommandoene med egen snarvei. Alt annet i biblioteket nås med `raw`, så denne
# lista er bare de man spør om ofte. Navnene valideres før innlogging: en skrivefeil
# skal si «ukjent kommando», ikke sende deg til innlogging først.
KOMMANDOER = (
    "day", "activities", "sleep", "steps", "hr", "hrv",
    "stress", "body-battery", "weight", "readiness", "stats",
)


def hent(g, kommando: str, args) -> object:
    fra, til = dato(args.fra, 7), dato(args.til)
    if kommando == "activities":
        return g.get_activities_by_date(fra, til)
    if kommando == "sleep":
        return g.get_sleep_data(til)
    if kommando == "steps":
        return g.get_daily_steps(fra, til)
    if kommando == "hr":
        return g.get_heart_rates(til)
    if kommando == "hrv":
        return g.get_hrv_data(til)
    if kommando == "stress":
        return g.get_stress_data(til)
    if kommando == "body-battery":
        return g.get_body_battery(fra, til)
    if kommando == "weight":
        return g.get_weigh_ins(fra, til)
    if kommando == "readiness":
        return g.get_morning_training_readiness(til)
    if kommando == "stats":
        return g.get_stats_and_body(til)
    if kommando == "day":  # noqa: PLR0911 — én gren per kommando er lesbarere enn et oppslag
        ut = {"dato": til}
        for navn, kall in (
            ("stats", lambda: g.get_stats_and_body(til)),
            ("sleep", lambda: g.get_sleep_data(til)),
            ("hrv", lambda: g.get_hrv_data(til)),
            ("readiness", lambda: g.get_morning_training_readiness(til)),
            ("activities", lambda: g.get_activities_by_date(til, til)),
        ):
            try:
                ut[navn] = kall()
            except Exception as e:  # noqa: BLE001 — én manglende måling skal ikke velte dagen
                ut[navn] = {"feil": f"{type(e).__name__}: {e}"}
        return ut
    feil(3, f"ukjent kommando: {kommando}")
    return None


def main() -> None:
    p = argparse.ArgumentParser(prog="garmin", description="Hent egne data fra Garmin Connect.")
    p.add_argument("kommando", help="auth, " + ", ".join(KOMMANDOER) + ", raw, methods")
    p.add_argument("rest", nargs="*", help="for «raw»: metodenavn og argumenter")
    p.add_argument("--fra", help="startdato (ÅÅÅÅ-MM-DD). Standard: sju dager siden")
    p.add_argument("--til", help="sluttdato (ÅÅÅÅ-MM-DD). Standard: i dag")
    p.add_argument("--table", action="store_true", help="tabell i stedet for JSON")
    args = p.parse_args()

    if args.kommando == "auth":
        auth()
        return
    if args.kommando == "methods":
        from garminconnect import Garmin
        for m in sorted(x for x in dir(Garmin) if x.startswith("get_")):
            print(m)
        return

    # Alt som kan avvises uten nett, avvises uten nett — før innlogging, så en
    # skrivefeil ikke ser ut som et autentiseringsproblem.
    if args.kommando == "raw":
        if not args.rest:
            feil(3, "raw trenger et metodenavn — se «garmin.sh methods»")
        from garminconnect import Garmin
        if not callable(getattr(Garmin, args.rest[0], None)):
            feil(3, f"{args.rest[0]} finnes ikke — se «garmin.sh methods»")
    elif args.kommando not in KOMMANDOER:
        feil(3, f"ukjent kommando: {args.kommando} (prøv: {', '.join(KOMMANDOER)}, raw, methods)")
    for felt in (args.fra, args.til):
        dato(felt) if felt else None

    g = klient()
    if args.kommando == "raw":
        navn, *rest = args.rest
        try:
            skriv(getattr(g, navn)(*rest), args.table)
        except Exception as e:  # noqa: BLE001
            feil(5, f"{navn} feilet: {type(e).__name__}: {e}")
        return

    try:
        skriv(hent(g, args.kommando, args), args.table)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        feil(5, f"{args.kommando} feilet: {type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
