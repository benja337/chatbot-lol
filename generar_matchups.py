#!/usr/bin/env python3
# baja partidas ranked de la API de Riot y arma datos_matchups.pl
#
# key en developer.riotgames.com (dura 24h, y si la regeneras la vieja muere al tiro)
#   windows:    $env:RIOT_API_KEY="RGAPI-..."
#   linux/mac:  export RIOT_API_KEY="RGAPI-..."
#   python generar_matchups.py --partidas 2000
#
# con ctrl+c guarda lo que lleva y despues sigue desde cache_matchups.json
# limite de la key: 100 peticiones cada 2 min -> 1000 partidas son como 25 min
import argparse
import json
import os
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections import deque

# cada servidor (plataforma) pertenece a una region, match-v5 se pide a la region
REGION_DE = {
    "na1": "americas", "br1": "americas", "la1": "americas", "la2": "americas",
    "euw1": "europe", "eun1": "europe", "tr1": "europe", "ru": "europe",
    "kr": "asia", "jp1": "asia",
    "oc1": "sea", "ph2": "sea", "sg2": "sea", "th2": "sea", "tw2": "sea", "vn2": "sea",
}
# nombres de riot -> como les decimos en el chatbot
ROLES = {"TOP": "top", "JUNGLE": "jungla", "MIDDLE": "mid", "BOTTOM": "adc", "UTILITY": "support"}
COLA_SOLO_DUO = 420  # ranked solo/duo
MAX_JUGADORES = 5000  # para que la cola no crezca infinito
# sin esto cloudflare tira 403 (error 1010) y parece que la key esta mala
USER_AGENT = "Mozilla/5.0 (chatbot-matchups)"


def norm(texto):
    # tiene que dar lo mismo que en generar_datos.py, si no no calzan los nombres
    sin_tildes = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    a = "".join(c for c in sin_tildes.lower() if c.isalnum())
    return ("x" + a) if (not a or a[0].isdigit()) else a


# todas las llamadas a la api pasan por aca, con pausa y reintentos
class Cliente:
    def __init__(self, api_key, plataforma, pausa):
        self.key = api_key
        self.plataforma = plataforma
        self.region = REGION_DE[plataforma]
        self.pausa = pausa
        self._ultimo = 0.0

    def get(self, host, ruta, params=None):
        url = f"https://{host}.api.riotgames.com{ruta}"
        if params:
            url += "?" + urllib.parse.urlencode(params)
        headers = {"X-Riot-Token": self.key, "User-Agent": USER_AGENT}
        for _ in range(5):  # hasta 5 intentos
            # esperar lo que falte para no pasarse del limite
            espera = self.pausa - (time.time() - self._ultimo)
            if espera > 0:
                time.sleep(espera)
            self._ultimo = time.time()
            req = urllib.request.Request(url, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    return json.load(r)
            except urllib.error.HTTPError as e:
                if e.code == 429:  # muchas peticiones, riot dice cuanto esperar
                    s = int(e.headers.get("Retry-After", "10")) + 1
                    print(f"  limite de peticiones, esperando {s}s...")
                    time.sleep(s)
                elif e.code == 404:  # no existe, no vale la pena reintentar
                    return None
                elif e.code in (401, 403):
                    sys.exit("API key invalida, vencida o regenerada (las de desarrollo duran 24 h). "
                             "Genera otra en developer.riotgames.com")
                elif e.code >= 500:  # falla de riot, esperar y probar de nuevo
                    time.sleep(5)
                else:
                    raise
            except urllib.error.URLError:  # sin internet / timeout
                time.sleep(5)
        return None


# jugadores desde donde parte la busqueda: uno puntual (--semilla) o
# los primeros de la liga EMERALD I por defecto
def obtener_semillas(cli, args):
    if args.semilla:
        if "#" not in args.semilla:
            sys.exit('Usa el formato --semilla "Nombre#TAG"')
        nombre, tag = args.semilla.rsplit("#", 1)
        ruta = "/riot/account/v1/accounts/by-riot-id/{}/{}".format(
            urllib.parse.quote(nombre, safe=""), urllib.parse.quote(tag, safe=""))
        cuenta = cli.get(cli.region, ruta)
        if not cuenta:
            sys.exit("No encontre a ese jugador (revisa nombre#TAG).")
        return [cuenta["puuid"]]

    entradas = cli.get(cli.plataforma,
                       f"/lol/league/v4/entries/RANKED_SOLO_5x5/{args.tier}/{args.division}",
                       {"page": 1}) or []
    puuids = []
    for e in entradas:
        p = e.get("puuid")
        if not p and e.get("summonerId"):  # a veces viene sin puuid
            s = cli.get(cli.plataforma, f"/lol/summoner/v4/summoners/{e['summonerId']}")
            p = s and s.get("puuid")
        if p:
            puuids.append(p)
        if len(puuids) >= args.semillas:
            break
    if not puuids:
        sys.exit("No pude obtener jugadores semilla. Prueba con --semilla \"Nombre#TAG\".")
    return puuids


def procesar_partida(partida, stats, prefijo_parche):
    # suma los enfrentamientos de cada linea, devuelve False si la partida no sirve
    info = partida.get("info", {})
    if info.get("queueId") != COLA_SOLO_DUO:
        return False
    if prefijo_parche and not info.get("gameVersion", "").startswith(prefijo_parche):
        return False
    parts = info.get("participants", [])
    if len(parts) != 10 or info.get("gameDuration", 0) < 300:
        return False
    if any(p.get("gameEndedInEarlySurrender") for p in parts):  # remakes
        return False

    # rol -> equipo -> jugadores en ese rol
    por_rol = {}
    for p in parts:
        rol = p.get("teamPosition")
        if rol in ROLES:
            por_rol.setdefault(rol, {}).setdefault(p["teamId"], []).append(p)

    usado = False
    for rol, equipos in por_rol.items():
        # uno por equipo, si no no se sabe quien jugo contra quien
        if set(equipos) != {100, 200} or any(len(v) != 1 for v in equipos.values()):
            continue
        a, b = equipos[100][0], equipos[200][0]
        ca, cb = norm(a["championName"]), norm(b["championName"])
        # se guarda para los dos lados: A vs B y B vs A
        for x, y, gano in ((ca, cb, a["win"]), (cb, ca, b["win"])):
            reg = stats.setdefault(f"{ROLES[rol]}|{x}|{y}", [0, 0])
            reg[0] += 1 if gano else 0
            reg[1] += 1
        usado = True
    return usado


# "mid|ahri|zed": [W, N]  ->  matchup(mid, ahri, zed, W, N).
def escribir_prolog(stats, total, ruta):
    with open(ruta, "w", encoding="utf-8") as f:
        f.write("% AUTOGENERADO por generar_matchups.py (API oficial de Riot, ranked solo/duo)\n")
        f.write("% matchup(Linea, Campeon, Rival, VictoriasDelCampeon, Partidas)\n")
        f.write(":- encoding(utf8).\n\n")
        f.write(f"matchups_partidas({total}).\n\n")
        for clave in sorted(stats):
            linea, a, b = clave.split("|")
            w, n = stats[clave]
            f.write(f"matchup({linea}, {a}, {b}, {w}, {n}).\n")


# para poder cortar y seguir despues
def cargar_cache(ruta):
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            d = json.load(f)
        return set(d["vistos"]), d["stats"]
    return set(), {}


def guardar_cache(ruta, vistos, stats):
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump({"vistos": sorted(vistos), "stats": stats}, f)


def ejecutar(cli, args):
    os.makedirs(args.salida, exist_ok=True)
    ruta_cache = os.path.join(args.salida, "cache_matchups.json")
    ruta_pl = os.path.join(args.salida, "datos_matchups.pl")
    if args.reiniciar and os.path.exists(ruta_cache):
        os.remove(ruta_cache)

    vistos, stats = cargar_cache(ruta_cache)
    # cuenta tambien las descartadas, da casi lo mismo
    usadas = len(vistos)
    print(f"Partidas ya en cache: {usadas}. Objetivo: {args.partidas}.")

    # semillas -> sus partidas -> los otros 9 de cada partida -> sus partidas...
    cola = deque(obtener_semillas(cli, args))
    jugadores = set(cola)
    try:
        while cola and usadas < args.partidas:
            puuid = cola.popleft()
            ids = cli.get(cli.region, f"/lol/match/v5/matches/by-puuid/{puuid}/ids",
                          {"queue": COLA_SOLO_DUO, "type": "ranked", "start": 0, "count": 20}) or []
            for mid in ids:  # mid = id de la partida, no la linea
                if usadas >= args.partidas:
                    break
                if mid in vistos:
                    continue
                partida = cli.get(cli.region, f"/lol/match/v5/matches/{mid}")
                if not partida:
                    continue
                vistos.add(mid)  # aunque no sirva, para no pedirla otra vez
                if procesar_partida(partida, stats, args.parche):
                    usadas += 1
                    if usadas % 10 == 0:  # cada 10 se guarda por si se corta
                        print(f"  {usadas}/{args.partidas} partidas (jugadores en cola: {len(cola)})")
                        guardar_cache(ruta_cache, vistos, stats)
                # los 10 jugadores de la partida pasan a la cola
                for p in partida.get("info", {}).get("participants", []):
                    if p["puuid"] not in jugadores and len(jugadores) < MAX_JUGADORES:
                        jugadores.add(p["puuid"])
                        cola.append(p["puuid"])
    except KeyboardInterrupt:
        print("\nInterrumpido: guardo lo que hay.")
    finally:
        # si la key se muere a la mitad igual se guarda lo que habia
        guardar_cache(ruta_cache, vistos, stats)
        escribir_prolog(stats, usadas, ruta_pl)

    print(f"Listo: {usadas} partidas, {len(stats)} enfrentamientos -> {ruta_pl}")


def main():
    ap = argparse.ArgumentParser(description="Enfrentamientos LoL desde la API de Riot")
    ap.add_argument("--api-key", default=os.environ.get("RIOT_API_KEY"))
    ap.add_argument("--plataforma", default="la2", choices=sorted(REGION_DE),
                    help="servidor (la2=LAS, la1=LAN, na1, br1, euw1, kr...)")
    ap.add_argument("--partidas", type=int, default=1000, help="partidas a analizar")
    ap.add_argument("--tier", default="EMERALD", help="rango de los jugadores semilla")
    ap.add_argument("--division", default="I", help="I, II, III o IV")
    ap.add_argument("--semillas", type=int, default=15, help="cantidad de jugadores semilla")
    ap.add_argument("--semilla", help='empezar desde un jugador: "Nombre#TAG"')
    ap.add_argument("--parche", help='solo partidas de un parche, ej: "16.5"')
    ap.add_argument("--pausa", type=float, default=1.25, help="segundos entre peticiones")
    ap.add_argument("--salida", default=".")
    ap.add_argument("--reiniciar", action="store_true", help="borrar la cache y empezar de cero")
    args = ap.parse_args()
    if not args.api_key:
        sys.exit("Falta la API key: define RIOT_API_KEY o usa --api-key")
    ejecutar(Cliente(args.api_key, args.plataforma, args.pausa), args)


if __name__ == "__main__":
    main()
