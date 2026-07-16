# 01 — Python Fundamentals

Progetto: **taskmanager/** — una task list da terminale.

## Esercizi (costruisci il progetto)

1. **Struttura progetto** — Crea `taskmanager/main.py`, `taskmanager/models.py`, `taskmanager/storage.py`. Usa `if __name__ == "__main__"`.

2. **Dataclass Task** — In `models.py` definisci `Task` con `id: int`, `title: str`, `done: bool = False`, `created_at: datetime`.

3. **CRUD in memoria** — In `storage.py` una classe `MemoryStorage` con `add`, `get`, `list`, `update`, `delete` su una lista in memoria.

4. **CLI con argparse** — In `main.py` un parser CLI: `python main.py add "comprare latte"`, `list`, `done 1`, `delete 1`.

5. **Type hints ovunque** — Aggiungi tipi a tutti i metodi. Usa `Optional`, `list[Task]`, `| None`.

6. **Pydantic model** — Sostituisci `dataclass` con Pydantic `BaseModel`. Aggiungi validazione: `title` minimo 3 caratteri.

7. **Enum** — Aggiungi `Priority(str, Enum): low, medium, high` a Task. Filtra per priorità nel CLI con `--priority high`.

8. **Context manager per file** — Crea `FileStorage` che salvi/carichi JSON. Usa context manager per apertura file.

9. **Generator per paginazione** — Aggiungi `list(page=1, per_page=10)` che restituisca un generatore paginato.

10. **async CLI** — Riscrivi `main.py` con `async def` e `asyncio.run()`. La storage salva su file in modo asincrono con `aiofiles`.
