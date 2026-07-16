# 05 — Database & ORM

Progetto: **taskmanager/** — sostituiamo la memoria volatile con un database.

## Esercizi

1. **SQLite con sqlite3** — Crea il DB, tabella `tasks(id INTEGER PK, title TEXT, done BOOLEAN, ...)`. Porta `MemoryStorage` a `SqliteStorage`.

2. **SQLAlchemy 2.0 models** — Definisci `Task`, `Project`, `Tag` con `mapped_column` e `Mapped`. Usa `declarative_base`.

3. **Session management** — Implementa `get_session()` come generator per FastAPI `Depends`. Ogni request ha la sua sessione.

4. **CRUD con SQLAlchemy** — Riscrivi tutti gli endpoint usando `select()`, `insert()`, etc. Usa `await db.execute()` con `AsyncSession`.

5. **Relationships** - Task → Project (M:1), Task → Tag (M:N). Carica con `selectinload()`.

6. **Alembic** — Inizializza, crea migration automatica per `Task`. Poi aggiungi `Project` e crea migration manuale.

7. **Migration di produzione** — Simula un alter table: aggiungi campo `due_date` a Task. Crea migration, esegui, verifica.

8. **N+1 query** — Crea una lista task con nome project. Senza eager loading fai 100 query. Poi risolvi con `selectinload()`.

9. **Transaction** — Endpoint `POST /projects/{pid}/tasks/bulk`: crea 10 task in una transazione. Se uno fallisce, rollback totale.

10. **PostgreSQL via Docker** — Cambia da SQLite a PostgreSQL. Usa `asyncpg`. Avvia PostgreSQL con `docker compose up -d`.
