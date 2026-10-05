% texto del usuario -> lista de palabras (tokens)
% y buscar que campeones / lineas nombro

:- encoding(utf8).

% minusculas y sin tildes
normalizar([], []).
normalizar([C|Cs], [N|Ns]) :- limpiar(C, N), normalizar(Cs, Ns).

% emojis -> espacio, en windows rompian el split_string
limpiar(C, 0' ) :- C > 0xFFFF, !.
limpiar(C, N) :- C >= 0'A, C =< 0'Z, !, N is C + 32.
limpiar(0'á, 0'a) :- !.
limpiar(0'é, 0'e) :- !.
limpiar(0'í, 0'i) :- !.
limpiar(0'ó, 0'o) :- !.
limpiar(0'ú, 0'u) :- !.
limpiar(0'ü, 0'u) :- !.
limpiar(0'ñ, 0'n) :- !.
limpiar(0'Á, 0'a) :- !.
limpiar(0'É, 0'e) :- !.
limpiar(0'Í, 0'i) :- !.
limpiar(0'Ó, 0'o) :- !.
limpiar(0'Ú, 0'u) :- !.
limpiar(0'Ü, 0'u) :- !.
limpiar(0'Ñ, 0'n) :- !.
limpiar(C, C).

tokenizar(Codes, Tokens) :-
    normalizar(Codes, Norm0),
    exclude(==(39), Norm0, Norm),   % saca el ' (Kai'Sa -> kaisa)
    atom_codes(Atom, Norm),
    split_string(Atom, " ,.;:?!¿¡&", "", Parts),
    exclude([S0]>>string_length(S0, 0), Parts, Clean),
    maplist([S, A]>>atom_string(A, S), Clean, Tokens0),
    unir_nombres(Tokens0, Tokens).

% lee sin -> leesin, miss fortune -> missfortune
unir_nombres([A,B|R], [AB|R2]) :-
    atom_concat(A, B, AB), campeon_alias(AB, _), !,
    unir_nombres(R, R2).
unir_nombres([A|R], [A|R2]) :- unir_nombres(R, R2).
unir_nombres([], []).

% formas de decir cada linea
alias_linea(top, top).
alias_linea(jungla, jungla).
alias_linea(jungle, jungla).
alias_linea(jg, jungla).
alias_linea(mid, mid).
alias_linea(medio, mid).
alias_linea(adc, adc).
alias_linea(bot, adc).
alias_linea(tirador, adc).
alias_linea(support, support).
alias_linea(supp, support).
alias_linea(soporte, support).
alias_linea(apoyo, support).

buscar_linea(Ts, L) :- member(T, Ts), alias_linea(T, L), !.

% con repetidos ("garen o garen" -> [garen, garen]), sirve para el espejo
menciones(Ts, Ms) :-
    findall(C, (member(T, Ts), campeon_alias(T, C)), Ms).

% sin repetidos, en el orden en que los escribio
campeones_en(Ts, Cs) :-
    menciones(Ts, Ms),
    list_to_set(Ms, Cs).

buscar_campeon(Ts, C) :- campeones_en(Ts, [C|_]).

contiene(Ts, Palabras) :- member(P, Palabras), member(P, Ts), !.
