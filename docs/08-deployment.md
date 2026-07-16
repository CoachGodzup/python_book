# 08 — Deployment & DevOps

Progetto: **taskmanager/** — portiamo in produzione.

## Esercizi

1. **Dockerfile multi-stage** — Stage `builder` (installa dipendenze), stage `runtime` (solo venv + codice). Usa immagine slim.

2. **docker-compose** — Definisci servizi: `api`, `db` (PostgreSQL), `redis`. Collega con network interno.

3. **Environment** — Usa `pydantic-settings` per leggere `DATABASE_URL`, `SECRET_KEY`, `REDIS_URL` da `.env`. `.env` non in git.

4. **Entrypoint** — Script `entrypoint.sh` che aspetta il DB (`pg_isready`), esegue migration, poi avvia uvicorn.

5. **Gunicorn + Uvicorn** — Sostituisci `uvicorn` diretto con `gunicorn -k uvicorn.workers.UvicornWorker` per multi-processo.

6. **Reverse proxy** — Aggiungi nginx prima dell'app: serve file statici, termina TLS, proxy_pass a gunicorn su localhost.

7. **GitHub Actions CI** — Workflow: `lint` (ruff), `test` (pytest + coverage), `build` (docker image), `push` su Docker Hub / GHCR.

8. **Health check** — Endpoint `GET /health` che verifica: app, DB (`SELECT 1`), Redis (`PING`). Usato da Docker e load balancer.

9. **Graceful shutdown** — Gestisci `SIGTERM`: chiudi connessioni DB, completa request in corso, ferma worker.

10. **Deploy su Railway/Fly.io** — Crea `fly.toml` o `railway.json`. Deploya. Configura dominio custom e TLS automatico.
