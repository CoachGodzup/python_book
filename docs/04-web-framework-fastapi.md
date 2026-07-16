# 04 — Web Framework (FastAPI)

Progetto: **taskmanager/** — portiamo tutto su FastAPI.

## Esercizi

1. **FastAPI setup** — Crea `app/main.py` con `FastAPI()`, monta il CRUD di task. Sostituisci il server HTTP manuale.

2. **Path/query params automatici** — Usa i type hint di FastAPI per validare `task_id: int`, `done: bool | None = None`, `page: int = 1`.

3. **Pydantic richiesta/risposta** — Definisci `TaskCreate`, `TaskResponse`, `TaskUpdate`. Usa `response_model=TaskResponse`.

4. **Dependency injection** — Crea un `Depends(get_storage)` che restituisca l'istanza di `MemoryStorage`. Tutte le route lo usano.

5. **Router modulari** — Struttura:
   ```
   app/
     main.py
     routers/
       __init__.py
       tasks.py
       projects.py
       tags.py
   ```

6. **Middleware custom** — Logga ogni richiesta con `time()`: `method path → status_code (durata ms)`.

7. **Exception handlers globali** — Cattura `TaskNotFound`, `ValidationError`, `HTTPException` generico. Tutti col formato `ApiError`.

8. **Background task** — `POST /tasks/{id}/reminder` accoda un reminder via `BackgroundTasks`. Logga "Reminder scaduto" dopo 10s.

9. **File upload** — `POST /tasks/{id}/attachment` carica un file, lo salva in `uploads/`, aggiorna il task con `attachment_url`.

10. **WebSocket live** — `WS /ws/tasks` notifica in tempo reale quando un task viene creato/aggiornato/cancellato.
