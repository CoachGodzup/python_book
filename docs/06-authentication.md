# 06 — Autenticazione & Autorizzazione

Progetto: **taskmanager/** — proteggiamo l'API.

## Esercizi

1. **User model** — Aggiungi tabella `users(id, email, hashed_password, created_at)`. Un task appartiene a un utente (`owner_id`).

2. **Registrazione** — `POST /auth/register` accetta `email`, `password`. Hash con `bcrypt`. Salva utente. Restituisci `201`.

3. **Login e JWT** — `POST /auth/login` verifica credenziali, restituisce `{"access_token": ..., "token_type": "bearer"}`. Usa `python-jose` / `PyJWT`.

4. **Dependency `get_current_user`** — Estrae il token da `Authorization: Bearer`, decodifica, carica l'utente dal DB. Proteggi tutte le route tranne auth.

5. **Refresh token** — Invia anche un `refresh_token` con expiry più lungo. Crea `POST /auth/refresh` per ottenere un nuovo access token.

6. **RBAC base** — Ruoli: `user`, `admin`. Solo admin può cancellare task altrui o vedere `GET /admin/users`. Usa `Depends(require_role("admin"))`.

7. **Rate limiting** — Aggiungi `slowapi`: max 100 request/min per utente, 5/min per `POST /auth/login`.

8. **API keys per servizi** — Crea tabella `api_keys(key, user_id, scopes)`. Un middleware accetta `X-API-Key` oltre a Bearer.

9. **Password reset flow** — `POST /auth/forgot-password` (invia magic link), `POST /auth/reset-password` (token + nuova password).

10. **OAuth2 social login** — Aggiungi login con Google/GitHub usando `authlib`. Crea utente se non esiste, restituisci JWT.
