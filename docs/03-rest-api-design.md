# 03 — REST API Design

Progetto: **taskmanager/** — riscriviamo l'API con design REST pulito.

## Esercizi

1. **Risorse** — Identifica le risorse: `tasks`, `projects`, `tags`. Disegna su carta l'albero delle rotte.

2. **URL scheme** — Implementa:
   - `GET /api/v1/tasks`
   - `POST /api/v1/tasks`
   - `GET /api/v1/tasks/{id}`
   - `PUT /api/v1/tasks/{id}`
   - `DELETE /api/v1/tasks/{id}`

3. **Nested resources** — Ogni task appartiene a un project: `GET /api/v1/projects/{pid}/tasks`. Non superare 2 livelli.

4. **Paginazione consistente** — Includi nella risposta:
   ```json
   {"data": [...], "page": 1, "per_page": 10, "total": 42}
   ```
   Header `X-Total-Count`.

5. **Filtri e sorting** — `GET /tasks?sort=created_at&order=desc&status=open&priority=high`

6. **Errori uniformi** — Schema `ApiError(detail: str, code: str, status: int)`. Ogni errore include un `trace_id`.

7. **HATEOAS minimo** — Ogni risorsa include `_links`:
   ```json
   {"_links": {"self": "/v1/tasks/1", "update": "/v1/tasks/1", "delete": "/v1/tasks/1"}}
   ```

8. **Bulk operations** — `POST /api/v1/tasks/bulk` accetta `{"tasks": [...]}` e crea tutto in un colpo.

9. **Soft delete** — `DELETE` imposta `deleted_at`. `GET /tasks` esclude soft-deleted. `GET /tasks?deleted=true` li mostra.

10. **Versioning** — Raddoppia il prefix router: `/v1/` (attuale) e `/v2/` (usa `_links` obbligatorio e campi snake_case). Confronta.
