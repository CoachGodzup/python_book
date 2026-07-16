# 10 — Concetti Avanzati

Progetto: **taskmanager/** — scaliamo e aggiungiamo complessità reale.

## Esercizi

1. **Celery + Redis** — Sposta l'invio email di reminder a un task Celery. `worker` separato, flower per monitoraggio.

2. **Caching con Redis** — Cachea `GET /tasks?page=1` per 30s. Invalida su POST/PUT/DELETE del task. Usa `redis-py` + `fastapi-cache`.

3. **CQRS base** — Comandi (POST/PUT/DELETE) vanno sul DB principale. Letture (GET) vanno su una replica read-only.

4. **Event Sourcing minimo** — Ogni modifica a un task produce un evento `TaskCreated`, `TaskUpdated`, `TaskDeleted`. Salva in `events` table. Proietta lo stato corrente.

5. **gRPC service** — Crea un server gRPC per `TaskService` (GetTask, ListTasks). Il client è un microservizio interno.

6. **GraphQL (Strawberry)** — Aggiungi `/graphql` accanto a REST. Query: `tasks(done: true) { id title project { name } }`.

7. **API Gateway pattern** — Un servizio gateway (FastAPI leggero) instrada a `task-service`, `user-service`, `notification-service`. Ognuno su porta diversa.

8. **Circuit breaker** — Avvolgi le chiamate al servizio notification con `pybreaker`: 3 fallimenti → aperto 30s.

9. **Idempotency key** — `POST /tasks` accetta `Idempotency-Key` header. Se stessa key arriva entro 24h, restituisci stessa risposta senza creare duplicato.

10. **Feature flags** — Integra `flagpole` o un semplice toggle DB: `GET /tasks?include_archived=true` solo se feature flag `ARCHIVED_TASKS` è attivo.
