% Reglas del dominio
%
% hechos (en los archivos datos_*.pl):
%   campeon_nombre(Id, Nombre)
%   campeon_clase(Id, Clase)
%   campeon_alias(Texto, Id)
%   matchup(Linea, A, B, W, N)  -> A jugo N partidas contra B en esa linea y gano W

:- encoding(utf8).

min_partidas(3).    % con menos no lo contamos
z95(1.96).

% R1 - intervalo de Wilson (95%) para W victorias de N
% para que 3/3 no valga mas que 60/100
intervalo(W, N, Low, High) :-
    N > 0,
    z95(Z),
    P is W / N,
    Z2 is Z * Z,
    Centro is P + Z2 / (2 * N),
    Margen is Z * sqrt(P * (1 - P) / N + Z2 / (4 * N * N)),
    Den is 1 + Z2 / N,
    Low is (Centro - Margen) / Den,
    High is (Centro + Margen) / Den.

% R2 - confianza segun partidas: 30+ alta, 10-29 media, menos baja
confianza(N, alta)  :- N >= 30, !.
confianza(N, media) :- N >= 10, !.
confianza(_, baja).

% R3 - veredicto
% ventaja_clara si hasta el limite inferior pasa el 50%
% desventaja_clara si ni el limite superior llega al 50%
% si el intervalo cruza el 50% queda como "leve"
veredicto(W, N, ventaja_clara)    :- intervalo(W, N, Low, _),  Low  > 0.5, !.
veredicto(W, N, desventaja_clara) :- intervalo(W, N, _, High), High < 0.5, !.
veredicto(W, N, ventaja_leve)     :- 2 * W > N, !.
veredicto(W, N, desventaja_leve)  :- 2 * W < N, !.
veredicto(_, _, parejo).

% R4 - matchup_fiable(L,A,B,W,N) <- matchup(L,A,B,W,N) ^ N >= min ^ A \= B
matchup_fiable(L, A, B, W, N) :-
    matchup(L, A, B, W, N),
    A \== B,
    min_partidas(Min),
    N >= Min.

% R5 - lineas donde hay datos del rival, de la con mas partidas a la con menos
% Pares = [Total-Linea, ...]
lineas_rival(C, Pares) :-
    setof(L, A^W^N^matchup(L, A, C, W, N), Ls),
    findall(Total-L,
            ( member(L, Ls),
              aggregate_all(sum(N), matchup(L, _, C, _, N), Total) ),
            Ps),
    sort(0, @>=, Ps, Pares).

% R6 - los K mejores contra Rival, ordenados por el limite inferior
mejores_contra(Rival, L, K, Lista) :-
    findall(r(Low, X, W, N, High),
            ( matchup_fiable(L, X, Rival, W, N), intervalo(W, N, Low, High) ),
            Rs),
    sort(0, @>=, Rs, Ord),
    primeros(K, Ord, Lista).

% R7 - los K peores: evitar(X, Rival) <- matchup_fiable(X, Rival) ^ W/N < 50%
peores_contra(Rival, L, K, Lista) :-
    findall(r(High, X, W, N, Low),
            ( matchup_fiable(L, X, Rival, W, N), 2 * W < N, intervalo(W, N, Low, High) ),
            Rs),
    sort(0, @=<, Rs, Ord),
    primeros(K, Ord, Lista).

% R8 - A vs B, en la linea donde mas se han enfrentado
enfrentamiento(A, B, L, W, N) :-
    findall(N0-L0-W0, ( matchup(L0, A, B, W0, N0), A \== B ), Ps),
    Ps \== [],
    sort(0, @>=, Ps, [N-L-W|_]).

primeros(K, L, P) :- length(P, K), append(P, _, L), !.
primeros(_, L, L).
