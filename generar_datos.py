#!/usr/bin/env python3
# baja los campeones de Data Dragon (no pide key) y crea datos_campeones.pl
# uso: python generar_datos.py   (o python3 en linux/mac)
#      python generar_datos.py --champion-json champion.json   si no hay internet
import argparse
import json
import os
import unicodedata
import urllib.request
from collections import Counter

# data dragon: archivos estaticos de riot (campeones, items, etc) por version
BASE = "https://ddragon.leagueoflegends.com"
# tags de riot -> clase en espanol
CLASES = {"Mage": "mago", "Assassin": "asesino", "Fighter": "luchador",
          "Tank": "tanque", "Marksman": "tirador", "Support": "apoyo"}
# sin esto cloudflare a veces bloquea (error 1010)
HEADERS = {"User-Agent": "Mozilla/5.0 (chatbot-matchups)"}


def descargar(url):
    print(f"  descargando {url}")
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def norm(texto):
    # Kai'Sa -> kaisa, Lee Sin -> leesin
    s = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    return "".join(c for c in s.lower() if c.isalnum())


def atomo(texto):
    # en prolog un atomo no puede empezar con numero
    a = norm(texto)
    return ("x" + a) if (not a or a[0].isdigit()) else a


# texto entre comillas simples para prolog, escapando \ y '
def q(texto):
    return "'" + texto.replace("\\", "\\\\").replace("'", "\\'") + "'"


# por campeon escribe campeon_nombre, sus campeon_clase y todos sus campeon_alias
def escribir_campeones(champs, version, ruta):
    # cuantos campeones empiezan con cada palabra (para el alias corto)
    primeras = Counter(norm(c["name"].split()[0]) for c in champs.values())
    with open(ruta, "w", encoding="utf-8") as f:
        f.write("% AUTOGENERADO por generar_datos.py - no editar a mano\n")
        f.write("% campeon_nombre(Id, Nombre). campeon_clase(Id, Clase). campeon_alias(Texto, Id).\n")
        f.write(":- encoding(utf8).\n")
        f.write(":- discontiguous campeon_nombre/2, campeon_clase/2, campeon_alias/2.\n\n")
        f.write(f"parche_datos({q(version)}).\n\n")
        for cid in sorted(champs):
            c = champs[cid]
            a = atomo(cid)
            f.write(f"campeon_nombre({a}, {q(c['name'])}).\n")
            for tag in c.get("tags", []):
                if tag in CLASES:
                    f.write(f"campeon_clase({a}, {CLASES[tag]}).\n")
            alias = {atomo(cid), atomo(c["name"])}
            # 'jarvan' -> JarvanIV, solo si nadie mas empieza igual
            primera = norm(c["name"].split()[0])
            if len(primera) >= 4 and primeras[primera] == 1:
                alias.add(primera)
            for al in sorted(alias):
                f.write(f"campeon_alias({al}, {a}).\n")
            f.write("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--salida", default=".")
    ap.add_argument("--champion-json", help="champion.json local (modo sin internet)")
    args = ap.parse_args()

    print("Obteniendo campeones de Data Dragon...")
    if args.champion_json:
        with open(args.champion_json, encoding="utf-8") as f:
            cj = json.load(f)
        version = cj.get("version", "local")
    else:
        version = descargar(f"{BASE}/api/versions.json")[0]  # la primera es la mas nueva
        cj = descargar(f"{BASE}/cdn/{version}/data/en_US/champion.json")

    os.makedirs(args.salida, exist_ok=True)
    escribir_campeones(cj["data"], version, os.path.join(args.salida, "datos_campeones.pl"))
    print(f"Parche {version}: {len(cj['data'])} campeones -> datos_campeones.pl")


if __name__ == "__main__":
    main()
