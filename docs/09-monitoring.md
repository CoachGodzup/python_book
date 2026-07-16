# 09 — Monitoring & Observability

Progetto: **taskmanager/** — vediamo cosa succede in produzione.

## Esercizi

1. **Logging strutturato** — Sostituisci `print()` e `logging` base con `structlog`. Configura output JSON.

2. **Rich logging in dev** — In sviluppo, usa `structlog` con `ConsoleRenderer` colorato. In produzione, JSON puro.

3. **Middleware di tracing** — Ogni request ha un `trace_id` (UUID generato all'inizio). Loggalo in ogni log della request.

4. **OpenTelemetry setup** — Installa `opentelemetry-api`, `opentelemetry-sdk`, `opentelemetry-instrumentation-fastapi`. Esporta trace in console.

5. **Health endpoint avanzato** — `GET /health` include: uptime, versione app, stato DB e Redis, memoria usata.

6. **Metriche Prometheus** — Usa `prometheus-fastapi-instrumentator`. Esponi `/metrics` con: request count, latency histogram, errori per status.

7. **Struttura log errori** — Tutti gli errori 500 loggano: `trace_id`, `user_id` (se autenticato), `path`, `method`, `stack_trace`. Mai loggare password o token.

8. **ALERTS** — Scrivi in un file `alerts.md` quali condizioni dovrebbero allertare: 5xx > 1% in 5 min, p99 latency > 2s, DB down.

9. **Structured context** — In ogni log, passa `logger.bind(user_id=uid, project_id=pid)` per avere campi contestuali.

10. **Centralized logging** — Aggiungi un handler che invia log a Loki (via `python-logging-loki`) o a un file JSON ruotato.
