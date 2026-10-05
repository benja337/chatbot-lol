% que pregunto el usuario y que le respondemos (usa reglas.pl)

:- encoding(utf8).

texto_veredicto(ventaja_clara,    "ventaja clara").
texto_veredicto(ventaja_leve,     "ventaja leve (sin certeza)").
texto_veredicto(parejo,           "parejo").
texto_veredicto(desventaja_leve,  "desventaja leve (sin certeza)").
texto_veredicto(desventaja_clara, "desventaja clara").

% queda tipo: 1. Lissandra: 58.1% de victorias (43 de 74 partidas) | ventaja clara | confianza alta
lineas_texto([], _, []).
lineas_texto([r(_, X, W, N, _)|Rs], I, [Linea|Ls]) :-
    campeon_nombre(X, Nom),
    Pct is W * 100 / N,
    veredicto(W, N, V), texto_veredicto(V, TV),
    confianza(N, Conf),
    format(string(Linea), "~d. ~w: ~1f% de victorias (~d de ~d partidas) | ~w | confianza ~w",
           [I, Nom, Pct, W, N, TV, Conf]),
    I1 is I + 1,
    lineas_texto(Rs, I1, Ls).

% si pidio una linea y hay datos usamos esa, si no la que tenga mas partidas
elegir_linea(T, Pares, L, Aviso) :-
    (   buscar_linea(T, LU)
    ->  (   memberchk(_-LU, Pares)
        ->  L = LU, Aviso = ""
        ;   Pares = [_-L|_],
            format(string(Aviso), "No tengo datos de ese campeon en ~w; te muestro ~w.\n", [LU, L])
        )
    ;   Pares = [_-L|_], Aviso = ""
    ).

otras_lineas(Pares, L, Nota) :-
    findall(T, ( member(N-L2, Pares), L2 \== L, format(string(T), "~w (~d partidas)", [L2, N]) ), Ts),
    (   Ts == []
    ->  Nota = ""
    ;   atomic_list_concat(Ts, ', ', S),
        format(string(Nota), "\nTambien hay datos en: ~w. Pregunta, por ejemplo, 'contra X en ~w'.",
               [S, L])
    ).

% cosas de las que no tenemos datos
fuera_de_tema([item, items, objeto, objetos, build, builds, comprar, compro, compra,
               runa, runas, hechizo, hechizos, habilidad, habilidades, skill, skills, combo]).

% ---- intenciones ----
% OJO el orden importa, se queda con la primera que calce

responder(T, R) :-
    contiene(T, [hola, buenas, hey, saludos]),
    \+ buscar_campeon(T, _), !,
    R = "Hola! Dime contra que campeon juegas y te digo cual conviene elegir. Ejemplo: 'estoy jugando contra Zed'. Escribe 'ayuda' para mas.".

responder(T, R) :-
    contiene(T, [ayuda, help]), !,
    R = "Ejemplos:\n  - estoy jugando contra Zed, que campeon me conviene?\n  - contra Yasuo en top\n  - Ahri vs Zed\n  - que campeon debo evitar contra Jinx\n  - como calculas esto (criterio)\n  - cuantas partidas analizaste\n  - salir".

% tiene que ir antes de las de campeones, si no "items para sona" lo toma como "contra sona"
responder(T, R) :-
    fuera_de_tema(Palabras),
    contiene(T, Palabras), !,
    R = "Solo analizo enfrentamientos entre campeones (quien le gana a quien). No tengo datos de items, runas ni builds. Prueba: 'contra Sylas en mid'.".

responder(T, R) :-
    contiene(T, [criterio, metodo, calculas, calcula, certeza, confiable, confianza]),
    \+ buscar_campeon(T, _), !,
    min_partidas(Min),
    format(string(R),
      "Uso partidas reales (ranked solo/duo, API de Riot). Para cada campeon X contra tu rival cuento victorias y partidas, y calculo el intervalo de confianza de Wilson al 95%. Ordeno por el limite INFERIOR: asi 3 victorias de 3 no le gana a 60 de 100. Ignoro enfrentamientos con menos de ~d partidas. 'Ventaja clara' = incluso el peor caso del intervalo supera el 50%. Confianza: alta (30+ partidas), media (10-29), baja (menos).",
      [Min]).

responder(T, R) :-
    contiene(T, [datos, partidas, fuente, cuantas, cuantos]),
    \+ buscar_campeon(T, _), !,
    (   matchups_partidas(N)
    ->  format(string(R), "Mis estadisticas salen de ~d partidas ranked solo/duo obtenidas con la API oficial de Riot.", [N])
    ;   R = "No tengo estadisticas cargadas. Ejecuta: python generar_matchups.py"
    ).

% garen vs garen
responder(T, R) :-
    campeones_en(T, [C]),
    menciones(T, [_, _|_]), !,
    campeon_nombre(C, Nom),
    format(string(R), "~w vs ~w es un enfrentamiento espejo: es el mismo campeon en los dos lados, asi que no hay ventaja (50%). Gana quien juegue mejor.", [Nom, Nom]).

% A vs B
responder(T, R) :-
    campeones_en(T, [A, B|_]), !,
    campeon_nombre(A, NA), campeon_nombre(B, NB),
    (   enfrentamiento(A, B, L, W, N)
    ->  Pct is W * 100 / N,
        intervalo(W, N, Lo, Hi),
        LoP is Lo * 100, HiP is Hi * 100,
        veredicto(W, N, V), texto_veredicto(V, TV),
        confianza(N, Conf),
        min_partidas(Min),
        (   N < Min -> Nota = "\nMuestra demasiado pequena: no es una conclusion fiable." ; Nota = "" ),
        format(string(R),
               "~w vs ~w (~w): ~w gano ~d de ~d partidas (~1f%).\nIntervalo de confianza 95%: ~1f% a ~1f%.\nPara ~w: ~w, confianza ~w.~w",
               [NA, NB, L, NA, W, N, Pct, LoP, HiP, NA, TV, Conf, Nota])
    ;   format(string(R), "No tengo partidas de ~w contra ~w.", [NA, NB])
    ).

% que no elegir contra X
responder(T, R) :-
    contiene(T, [evitar, evito, peor, peores, malo, malos, debil, debiles]),
    buscar_campeon(T, C), !,
    campeon_nombre(C, Nom),
    (   lineas_rival(C, Pares)
    ->  elegir_linea(T, Pares, L, Aviso),
        peores_contra(C, L, 5, Lista),
        (   Lista == []
        ->  min_partidas(Min),
            format(string(R), "~wNo hay ningun campeon con desventaja comprobada contra ~w en ~w (con al menos ~d partidas).",
                   [Aviso, Nom, L, Min])
        ;   lineas_texto(Lista, 1, Ls), atomic_list_concat(Ls, '\n', Cuerpo),
            format(string(R), "~wContra ~w en ~w, mejor EVITAR:\n~w", [Aviso, Nom, L, Cuerpo])
        )
    ;   format(string(R), "No tengo partidas de ~w en mis datos.", [Nom])
    ).

% que elegir contra X, la principal
responder(T, R) :-
    buscar_campeon(T, C), !,
    campeon_nombre(C, Nom),
    (   lineas_rival(C, Pares)
    ->  elegir_linea(T, Pares, L, Aviso),
        memberchk(Total-L, Pares),
        min_partidas(Min),
        mejores_contra(C, L, 5, Lista),
        (   Lista == []
        ->  format(string(R),
                   "~wHay datos de ~w en ~w (~d partidas), pero ningun enfrentamiento llega a ~d partidas. Hacen falta mas datos (python generar_matchups.py --partidas 3000).",
                   [Aviso, Nom, L, Total, Min])
        ;   include([r(_, _, W, N, _)]>>(2 * W > N), Lista, Positivos),
            otras_lineas(Pares, L, Nota),
            (   Positivos \== []
            ->  lineas_texto(Positivos, 1, Ls), atomic_list_concat(Ls, '\n', Cuerpo),
                format(string(R),
                       "~wContra ~w en ~w (~d partidas analizadas), mejores opciones:\n~w~w\n(Ordenado por certeza estadistica. Escribe 'criterio' para ver el metodo.)",
                       [Aviso, Nom, L, Total, Cuerpo, Nota])
            ;   lineas_texto(Lista, 1, Ls), atomic_list_concat(Ls, '\n', Cuerpo),
                format(string(R),
                       "~wContra ~w en ~w (~d partidas) ningun campeon tiene ventaja en mis datos. Los menos malos son:\n~w~w",
                       [Aviso, Nom, L, Total, Cuerpo, Nota])
            )
        )
    ;   format(string(R), "No tengo partidas de ~w en mis datos.", [Nom])
    ).

responder(T, R) :-
    contiene(T, [contra, vs, versus]), !,
    R = "No reconoci el campeon. Escribe su nombre, por ejemplo: 'estoy jugando contra Zed'.".

responder(_, "No entendi. Dime contra que campeon juegas (ej: 'contra Zed') o escribe 'ayuda'.").
