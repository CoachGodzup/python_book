# 02 — Fondamenti di Rete e HTTP

Progetto: **taskmanager/** — evolviamo la CLI in un server HTTP minimale.

## Esercizi

1. **Server HTTP base** — Usa `http.server` per esporre `GET /tasks` che restituisca JSON. Nessun framework.

2. **Endpoint CRUD via HTTP** — Aggiungi `POST /tasks`, `GET /tasks/{id}`, `PUT /tasks/{id}`, `DELETE /tasks/{id}`. Parsa il body JSON a mano.

3. **Status code** — Usa `201` per creazione, `204` per delete, `404` se task non trovato, `400` se body non valido.

4. **Headers** — Aggiungi `Content-Type: application/json` a tutte le response. Leggi `Authorization: Bearer <token>` dal request header.

5. **Query params** — Supporta `GET /tasks?done=true&priority=high&page=1&per_page=10`.

6. **CORS** — Aggiungi header `Access-Control-Allow-Origin: *` per permettere chiamate da un frontend su altra porta.

7. **cURL test** — Scrivi uno script bash che testi tutto il CRUD con `curl -v`. Osserva i dati viaggiare in chiaro.

8. **Cookie** — Aggiungi una rotta `POST /login` che setta un cookie `session_id` con `HttpOnly` e `SameSite=Lax`.

9. **Test con httpx** — Usa `httpx` da Python per testare tutti gli endpoint, verificando status code e body.

10. **HTTPS self-signed** — Genera certificato con `openssl`, avvia il server con supporto HTTPS. Verifica con `curl -k`.
