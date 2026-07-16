# Capitolo 7 — Testing: Strategie, Tooling, e TDD

## Filosofia: Testare Contratti, Non Implementazione

Un test backend valida:
1. **Status code** corretto
2. **Schema risposta** conforme (Pydantic)
3. **Stato DB** mutato come atteso
4. **Errori** nel formato standard (RFC 7807)
5. **Autorizzazione** applicata correttamente

Non testa: dettagli interni (quale query SQL, ordine chiamate service).

---

## Stack Testing

| Tool | Ruolo |
|------|-------|
| `pytest` | Runner, fixture, parametrizzazione, plugin ecosystem |
| `pytest-asyncio` | Supporto `async def` test |
| `httpx` / `TestClient` | Client HTTP in-process (no network) |
| `pytest-mock` / `unittest.mock` | Mock servizi esterni |
| `factory-boy` / `pytest-factoryboy` | Generazione dati test |
| `pytest-cov` | Coverage report |
| `sqlalchemy` + SQLite `:memory:` | DB isolato per test |

---

## Struttura `tests/`

```
tests/
├── conftest.py              # Fixture condivise
├── fixtures/
│   ├── users.py             # Factory User
│   └── tasks.py             # Factory Task
├── unit/
│   ├── test_security.py
│   └── test_services.py
├── integration/
│   ├── test_auth.py
│   ├── test_tasks_crud.py
│   └── test_projects.py
└── e2e/
    └── test_full_flow.py
```

---

## `conftest.py`: Fixture Fondamentali

```python
# tests/conftest.py
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from app.main import app
from app.core.database import Base, get_db
from app.core.config import get_settings

# --- Database in-memory per test ---
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

@pytest_asyncio.fixture(scope="session")
async def engine():
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()

@pytest_asyncio.fixture
async def db_session(engine):
    async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as session:
        yield session
        await session.rollback()  # Isolamento: rollback dopo ogni test

# --- Override dependency ---
@pytest_asyncio.fixture
async def client(db_session):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()

# --- Auth helper ---
@pytest_asyncio.fixture
async def auth_client(client, db_session):
    """Client autenticato come utente test standard."""
    from app.models.user import User
    from app.core.security import hash_password, create_access_token

    user = User(
        email="test@example.com",
        hashed_password=hash_password("testpass123"),
        is_active=True,
    )
    db_session.add(user)
    await db_session.flush()

    token = create_access_token(user.id)
    client.headers["Authorization"] = f"Bearer {token}"
    return client
```

---

## Factory Pattern per Dati Test

```python
# tests/fixtures/users.py
import factory
from factory.alchemy import SQLAlchemyModelFactory
from app.models.user import User
from app.core.security import hash_password

class UserFactory(SQLAlchemyModelFactory):
    class Meta:
        model = User
        sqlalchemy_session_persistence = "flush"

    email = factory.Sequence(lambda n: f"user{n}@example.com")
    hashed_password = factory.LazyAttribute(lambda _: hash_password("password123"))
    full_name = factory.Faker("name")
    is_active = True
    is_superuser = False

# Uso
@pytest.fixture
def user_factory(db_session):
    UserFactory._meta.sqlalchemy_session = db_session
    return UserFactory
```

---

## Test CRUD Completo

```python
# tests/integration/test_tasks_crud.py
import pytest
from httpx import AsyncClient
from uuid import UUID

class TestTasksCRUD:
    async def test_create_task(self, auth_client: AsyncClient):
        payload = {"title": "Nuovo task", "priority": "high"}
        resp = await auth_client.post("/api/v1/tasks", json=payload)
        assert resp.status_code == 201
        data = resp.json()
        assert data["title"] == "Nuovo task"
        assert data["priority"] == "high"
        assert "id" in data
        UUID(data["id"])  # Valido UUID

    async def test_list_tasks_pagination(self, auth_client: AsyncClient, user_factory):
        # Crea 25 task
        for i in range(25):
            await auth_client.post("/api/v1/tasks", json={"title": f"Task {i}"})

        resp = await auth_client.get("/api/v1/tasks?page=2&per_page=10")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["items"]) == 10
        assert data["page"] == 2
        assert data["total"] == 25

    async def test_get_task_not_found(self, auth_client: AsyncClient):
        resp = await auth_client.get("/api/v1/tasks/00000000-0000-0000-0000-000000000000")
        assert resp.status_code == 404
        assert resp.json()["code"] == "NOT_FOUND"

    async def test_update_task(self, auth_client: AsyncClient):
        create = await auth_client.post("/api/v1/tasks", json={"title": "Original"})
        task_id = create.json()["id"]

        resp = await auth_client.patch(f"/api/v1/tasks/{task_id}", json={"title": "Updated"})
        assert resp.status_code == 200
        assert resp.json()["title"] == "Updated"

    async def test_delete_task(self, auth_client: AsyncClient):
        create = await auth_client.post("/api/v1/tasks", json={"title": "To delete"})
        task_id = create.json()["id"]

        resp = await auth_client.delete(f"/api/v1/tasks/{task_id}")
        assert resp.status_code == 204

        resp = await auth_client.get(f"/api/v1/tasks/{task_id}")
        assert resp.status_code == 404
```

---

## Test Autorizzazione e Errori

```python
# tests/integration/test_auth.py
async def test_unauthorized_access(client: AsyncClient):
    resp = await client.get("/api/v1/tasks")
    assert resp.status_code == 401
    assert resp.json()["code"] == "UNAUTHORIZED"

async def test_forbidden_cross_user_access(auth_client: AsyncClient, user_factory, db_session):
    # Crea altro utente e suo task
    other = user_factory(email="other@example.com")
    from app.models.task import Task
    task = Task(title="Other's task", owner_id=other.id)
    db_session.add(task)
    await db_session.flush()

    resp = await auth_client.patch(f"/api/v1/tasks/{task.id}", json={"title": "Hacked"})
    assert resp.status_code == 403
    assert resp.json()["code"] == "FORBIDDEN"

async def test_validation_error(client: AsyncClient):
    resp = await client.post("/api/v1/tasks", json={"title": ""})  # Too short
    assert resp.status_code == 422
    data = resp.json()
    assert data["code"] == "VALIDATION_ERROR"
    assert any(e["field"] == "title" for e in data["errors"])
```

---

## Mock Servizi Esterni

```python
# tests/unit/test_services.py
from unittest.mock import AsyncMock, patch
import pytest
from app.services.email import send_password_reset_email

async def test_password_reset_sends_email(mock_send_email):
    with patch("app.services.email.sendgrid_send", new_callable=AsyncMock) as mock_send:
        mock_send.return_value = None
        await send_password_reset_email("user@example.com", "reset-token-123")
        mock_send.assert_awaited_once()
        args, kwargs = mock_send.call_args
        assert args[0] == "user@example.com"
        assert "reset-token-123" in args[1]
```

```python
# tests/conftest.py - fixture mock globale
@pytest.fixture(autouse=True)
def mock_external_services():
    with patch("app.services.payment.stripe.charge") as mock_charge, \
         patch("app.services.storage.s3.upload") as mock_upload:
        mock_charge.return_value = {"id": "ch_test", "status": "succeeded"}
        mock_upload.return_value = "https://cdn.example.com/file.pdf"
        yield
```

---

## Parametrizzazione: Un Test, Molti Casi

```python
@pytest.mark.parametrize("payload,expected_status,error_code", [
    ({"title": "Valid"}, 201, None),
    ({"title": ""}, 422, "VALIDATION_ERROR"),
    ({"title": "a" * 201}, 422, "VALIDATION_ERROR"),
    ({"title": "Valid", "priority": "invalid"}, 422, "VALIDATION_ERROR"),
    ({}, 422, "VALIDATION_ERROR"),
    (None, 422, "VALIDATION_ERROR"),
])
async def test_create_task_validation(auth_client, payload, expected_status, error_code):
    resp = await auth_client.post("/api/v1/tasks", json=payload)
    assert resp.status_code == expected_status
    if error_code:
        assert resp.json()["code"] == error_code
```

---

## Test Asincroni e Concorrenza

```python
@pytest.mark.asyncio
async def test_concurrent_creation(auth_client):
    import asyncio
    async def create_task(i):
        return await auth_client.post("/api/v1/tasks", json={"title": f"Task {i}"})

    responses = await asyncio.gather(*[create_task(i) for i in range(20)])
    assert all(r.status_code == 201 for r in responses)
    ids = [r.json()["id"] for r in responses]
    assert len(set(ids)) == 20  # Tutti univoci
```

---

## Coverage: Obiettivi e Esclusioni

```bash
# Esecuzione
pytest --cov=app --cov-report=term-missing --cov-report=html --cov-fail-under=85
```

```ini
# pyproject.toml
[tool.coverage.run]
source = ["app"]
omit = [
    "app/main.py",           # Solo wiring
    "app/core/config.py",    # Settings
    "app/core/logging.py",   # Config logging
    "*/migrations/*",
    "*/tests/*",
]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
]
```

> **Regola**: 85% coverage *minimo*, ma 100% su `auth`, `payments`, `security`, `error handlers`.

---

## TDD: Flusso per Feature Critiche

```python
# 1. RED: Scrivi test che fallisce
async def test_transfer_task_ownership(auth_client, other_user, db_session):
    task = await create_task(auth_client, owner=current_user)
    resp = await auth_client.post(f"/api/v1/tasks/{task.id}/transfer", json={"new_owner_id": str(other_user.id)})
    assert resp.status_code == 200
    assert resp.json()["owner_id"] == str(other_user.id)

# 2. GREEN: Implementa minimo per passare
@router.post("/tasks/{task_id}/transfer")
async def transfer_ownership(...):
    # ... logic ...
    return task

# 3. REFACTOR: Estrai service, aggiungi validazioni, test edge cases
```

---

## E2E: Flusso Completo Utente

```python
# tests/e2e/test_full_flow.py
async def test_user_journey_register_login_create_task(client, db_session):
    # 1. Registrazione
    resp = await client.post("/api/v1/auth/register", json={
        "email": "journey@example.com",
        "password": "SecurePass123",
        "full_name": "Journey User"
    })
    assert resp.status_code == 201

    # 2. Login
    resp = await client.post("/api/v1/auth/login", json={
        "email": "journey@example.com",
        "password": "SecurePass123"
    })
    assert resp.status_code == 200
    tokens = resp.json()
    client.headers["Authorization"] = f"Bearer {tokens['access_token']}"

    # 3. Crea task
    resp = await client.post("/api/v1/tasks", json={"title": "First task"})
    assert resp.status_code == 201

    # 4. Refresh token
    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert resp.status_code == 200
    new_tokens = resp.json()
    assert "access_token" in new_tokens
```

---

## Checklist Testing

- [ ] `conftest.py` con `db_session` (SQLite `:memory:`), `client`, `auth_client`
- [ ] Factory per ogni modello principale (`factory-boy`)
- [ ] Test CRUD per ogni risorsa (create, read, list, update, delete)
- [ ] Test errori: 401, 403, 404, 422, 409, 429
- [ ] Test autorizzazione: owner vs non-owner, role-based
- [ ] Mock servizi esterni (email, payment, storage, webhooks)
- [ ] Parametrizzazione per validazione input
- [ ] Test concorrenza per operazioni critiche
- [ ] Coverage ≥ 85% (100% su auth/security/payments)
- [ ] TDD per feature business-critical
- [ ] E2E per flussi chiave (register → login → create → refresh → logout)

---

## Glossario Capitolo 7

| Termine | Definizione |
|---------|-------------|
| **Fixture** | Funzione pytest che prepara/teardown contesto test (DB, client, utente) |
| **Parametrizazione** | `@pytest.mark.parametrize` esegue stesso test con input/expected differenti |
| **Mock** | Sostituisce dipendenza esterna con oggetto controllato (verifica chiamate, ritorna valori fissi) |
| **Factory** | Genera istanze modello con dati realistici/variati (`factory-boy`) |
| **Coverage** | % di linee/branche eseguite durante test |
| **TDD** | Test-Driven Development: Red (test fallisce) → Green (passa) → Refactor |
| **E2E Test** | Testa flusso utente completo attraverso API reali |
| **Integration Test** | Testa interazione tra componenti (API + DB + Auth) |

---

## Prossimo Capitolo

Nel **Capitolo 8** porteremo l'API in produzione: Docker multi-stage, docker-compose, environment variables, Gunicorn+Nginx, CI/CD GitHub Actions, e deploy su Railway/Fly.io.