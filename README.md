# Chatbot de matchups de LoL

Proyecto 2 - Fundamentos de Inteligencia Artificial

Integrantes:
- Felipe Ignacio Yelpi Bazignan
- Diego Andres Lizama Carrasco
- Benjamin antonio velasquez reyes 

## Dominio

El dominio son los **enfrentamientos entre campeones de League of Legends** (los "matchups").
La idea es que el usuario le diga al chatbot contra quien esta jugando y el chatbot le recomiende
que campeon elegir (o cual evitar), segun partidas reales.

Lo elegimos porque es un tema que conocemos bien como jugadores, asi que podemos revisar si las
respuestas tienen sentido. Ademas el conocimiento sale de datos reales (la API oficial de Riot)
y se presta para reglas logicas del tipo "X le gana a Y si...".

Ojo que el chatbot solo sabe de matchups. No sabe de items, runas ni builds, y si le preguntan
eso lo dice en vez de inventar.

## Base de conocimientos

Los hechos estan en dos archivos que se generan con los scripts de Python
(datos del parche 16.19.1, 4000 partidas ranked solo/duo del servidor LAS):

| Hecho | Que significa | Ejemplo | Cantidad |
|---|---|---|---|
| `campeon_nombre(Id, Nombre)` | nombre del campeon | `campeon_nombre(leesin, 'Lee Sin').` | 173 |
| `campeon_clase(Id, Clase)` | clase (mago, asesino, tanque...) | `campeon_clase(leesin, luchador).` | 303 |
| `campeon_alias(Texto, Id)` | como lo puede escribir el usuario | `campeon_alias(jarvan, jarvaniv).` | 182 |
| `matchup(Linea, A, B, W, N)` | A jugo N partidas contra B en esa linea y gano W | `matchup(mid, zed, ahri, 14, 21).` | 12036 |
| `alias_linea(Texto, Linea)` | formas de decir cada linea | `alias_linea(jg, jungla).` | 13 |

`campeon_*` estan en `datos_campeones.pl`, `matchup` en `datos_matchups.pl` y `alias_linea` en `lenguaje.pl`.

## Reglas (logica de primer orden)

Estan en `reglas.pl`. Notacion: `←` si, `∧` y, `∀` para todo.

- **R1 - intervalo(W, N, Low, High):** intervalo de confianza de Wilson al 95% para W victorias en N partidas.
  Sirve para que 3 de 3 no valga mas que 60 de 100.
- **R2 - confianza(N, Nivel):** ∀N: N ≥ 30 → alta; 10 ≤ N < 30 → media; N < 10 → baja.
- **R3 - veredicto(W, N, V):**
  - ventaja_clara(A, B) ← limite inferior del intervalo > 50%
  - desventaja_clara(A, B) ← limite superior del intervalo < 50%
  - ventaja_leve / desventaja_leve ← sobre o bajo 50% pero el intervalo cruza el 50%
- **R4 - matchup_fiable(L, A, B, W, N) ← matchup(L, A, B, W, N) ∧ N ≥ 3 ∧ A ≠ B**
- **R5 - lineas_rival(C, Pares):** lineas donde hay datos de C, ordenadas por cantidad de partidas.
  linea_con_datos(L, C) ← ∃A, W, N: matchup(L, A, C, W, N)
- **R6 - mejores_contra(Rival, L, K, Lista):** los K campeones X con matchup_fiable contra Rival,
  ordenados por el limite inferior del intervalo (no por el winrate bruto).
- **R7 - peores_contra(Rival, L, K, Lista):** evitar(X, Rival) ← matchup_fiable(L, X, Rival, W, N) ∧ W/N < 50%
- **R8 - enfrentamiento(A, B, L, W, N):** A vs B en la linea donde mas partidas hay.

## Que se le puede preguntar

```
> contra Zed
> contra Yasuo en top
> Ahri vs Zed
> que evito contra Jinx
> criterio
> cuantas partidas
> ayuda
> salir
```

Entiende mayusculas, tildes, nombres con espacio o apostrofe (lee sin, Kai'Sa) y apodos de lineas (jg, supp, bot).

## Como correrlo

Necesita [SWI-Prolog](https://www.swi-prolog.org/download/stable). Los datos ya vienen en el repo.

```
swipl -q -g main -t halt chatbot.pl
```

En Windows, si `swipl` no esta en el PATH, usar la ruta completa, por ejemplo
`"C:\Program Files\swipl\bin\swipl.exe" -q -g main -t halt chatbot.pl`.

### Con Docker (sin instalar Prolog)

```
docker build -t chatbot-lol .
docker run -it --rm chatbot-lol
```

## Volver a generar los datos

Solo si se quieren datos nuevos. Necesita Python 3 (sin librerias extra) y una API key de
https://developer.riotgames.com (la de desarrollo dura 24 h).

```
python generar_datos.py                      # campeones, no pide key
export RIOT_API_KEY="RGAPI-..."              # en PowerShell: $env:RIOT_API_KEY="RGAPI-..."
python generar_matchups.py --partidas 4000   # matchups
```

En Linux/Mac puede que sea `python3`. Si se corta con Ctrl+C, al volver a correrlo sigue donde quedo.

## Archivos

| Archivo | Que tiene |
|---|---|
| `chatbot.pl` | bucle principal, carga todo lo demas |
| `reglas.pl` | reglas R1 a R8 |
| `lenguaje.pl` | normaliza el texto y detecta campeones y lineas |
| `respuestas.pl` | intenciones del usuario y armado de las respuestas |
| `datos_campeones.pl` | hechos de campeones (generado) |
| `datos_matchups.pl` | hechos de matchups (generado) |
| `generar_datos.py` | baja los campeones de Data Dragon |
| `generar_matchups.py` | baja partidas de la API de Riot y cuenta los matchups |
| `Dockerfile` | para correrlo con Docker |
