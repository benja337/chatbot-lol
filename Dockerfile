# Etapa 1: descarga la lista de campeones desde Data Dragon
FROM python:3.12-slim AS datos
WORKDIR /datos
COPY generar_datos.py ./
RUN python generar_datos.py

# Etapa 2: el chatbot en SWI-Prolog
FROM swipl:latest
WORKDIR /app
ENV LANG=C.UTF-8
# datos_matchups.pl* -> generalo antes con generar_matchups.py (necesita tu API key y tarda)
COPY chatbot.pl reglas.pl lenguaje.pl respuestas.pl datos_matchups.pl* ./
COPY --from=datos /datos/datos_campeones.pl ./
CMD ["swipl", "-q", "-g", "main", "-t", "halt", "chatbot.pl"]
