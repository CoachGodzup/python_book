# 07 — Testing

Progetto: **taskmanager/** — copriamo tutto con test.

## Esercizi

1. **pytest setup** — Crea `tests/`, `conftest.py`, `pyproject.toml` con `[tool.pytest.ini_options]`. Scrivi un primo test che passa.

2. **Fixtures base** — `conftest.py`:
   - `client` → `TestClient(app)`
   - `db_session` → sessione DB temporanea
   - `test_user` → crea utente di test

3. **Test CRUD tasks** — Testa ogni endpoint: `test_create_task`, `test_get_task`, `test_update_task`, `test_delete_task`, `test_list_tasks`.

4. **Test errori** — Verifica 404 per task inesistente, 422 per body non valido, 401 senza token, 403 per permessi insufficienti.

5. **Test autenticazione** — `test_register`, `test_login_success`, `test_login_wrong_password`, `test_refresh_token`, `test_expired_token`.

6. **Test DB isolati** — Usa un DB SQLite `:memory:` per ogni test. Rollback o drop dopo ogni test. Mai dipendenza tra test.

7. **Mock esterno** — Se l'app manda email (password reset), mocka `smtplib` con `unittest.mock`. Verifica che la funzione sia stata chiamata.

8. **Parametrizzazione** — `@pytest.mark.parametrize` per testare più priorità, status, pagine con un solo test.

9. **Test asincroni** — Usa `pytest-asyncio` e `async` fixtures per testare gli endpoint async.

10. **Coverage** — Aggiungi `pytest-cov`. Obiettivo: >85%. Scrivi test per i branch mancanti.
