% Chatbot de matchups de LoL
% juegas contra X -> que campeon te conviene
%
% primero generar los datos:
%   python generar_datos.py
%   python generar_matchups.py   (necesita RIOT_API_KEY)
% correr:
%   swipl -q -g main -t halt chatbot.pl

:- encoding(utf8).

% vienen de datos_campeones.pl y datos_matchups.pl
:- dynamic parche_datos/1, campeon_nombre/2, campeon_clase/2, campeon_alias/2,
           matchup/5, matchups_partidas/1.

:- ensure_loaded(reglas).
:- ensure_loaded(lenguaje).
:- ensure_loaded(respuestas).

% si falta algun archivo no se cae aca, main avisa despues
cargar_datos(Archivo) :-
    prolog_load_context(directory, Dir),
    directory_file_path(Dir, Archivo, Ruta),
    (   exists_file(Ruta) -> ensure_loaded(Ruta) ; true ).

:- cargar_datos('datos_campeones.pl').
:- cargar_datos('datos_matchups.pl').


main :-
    usar_utf8(user_input),
    usar_utf8(user_output),
    verificar_datos,
    writeln('=== Chatbot de matchups LoL ==='),
    writeln('Dime contra que campeon juegas. (escribe "ayuda" o "salir")'),
    loop.

% en la consola de windows esto falla, pero ahi ya funciona con tildes igual
usar_utf8(Stream) :-
    catch(set_stream(Stream, encoding(utf8)), _, true).

verificar_datos :-
    (   campeon_nombre(_, _) -> true
    ;   writeln('Faltan los campeones. Ejecuta primero:  python generar_datos.py'), halt(1) ),
    (   matchup(_, _, _, _, _) -> true
    ;   writeln('Faltan las estadisticas. Ejecuta primero:  python generar_matchups.py'), halt(1) ).

loop :-
    write('> '), flush_output,
    read_line_to_codes(user_input, Codes),
    (   Codes == end_of_file
    ->  true
    ;   tokenizar(Codes, Tokens),
        (   despedida(Tokens)
        ->  writeln('Suerte en la grieta, invocador!')
        ;   responder(Tokens, R),
            format("Bot: ~w~n", [R]),
            loop
        )
    ).

% solo la palabra sola, "no quiero salir todavia" no deberia cerrar
despedida([P]) :- memberchk(P, [salir, chao, adios, exit, quit]).
