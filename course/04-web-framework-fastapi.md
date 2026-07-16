# Capitolo 4 — FastAPI: Framework per API Moderne

## Perché FastAPI

Tre opzioni principali per API Python:

| Framework | Filosofia | Punti di Forza | Trade-off |
|-----------|-----------|----------------|-----------|
| **Flask** | Micro, estensibile | Semplicità, ecosistema maturo | Boilerplate per validazione, auth, docs, async |
| **Django / DRF** | Batteries-included | Admin, ORM, auth, sicurezza out-of-the-box | Pesante, opinionato, async limitato (fino a 4.x) |
| **FastAPI** | Moderno, standard-based | OpenAPI nativo, Pydantic validation, async nativo, DI, performance Starlette | Ecosistema più giovane, meno "batterie" |

FastAPI è la scelta ottimale per **API-first, async-first, type-safe** services.

---

## Hello World Minimo

```python
# app/main.py
from fastapi import FastAPI

app = FastAPI(title="TaskManager API", version="1.0.0")

@app.get("/")
async def root() -> dict[str, str]:
    return {"message": "Hello World"}
```

Avvio:
```bash
uvicorn app.main:app --reload --port 8000
```

Documentazione interattiva automatica:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`
- OpenAPI JSON: `http://localhost:8000/openapi.json`

---

## Parametri: Path, Query, Header, Cookie

FastAPI usa **type hints** per validazione, parsing, documentazione.

```python
from fastapi import Path, Query, Header, Cookie
from typing import Annotated

@app.get("/items/{item_id}")
async def read_item(
    item_id: Annotated[int, Path(ge=1, description="ID numerico > 0")],
    q: Annotated[str | None, Query(min_length=3, max_length=50, pattern=r"^[\w-]+$")] = None,
    category: Annotated[str, Query(alias="cat")] = "general",
    x_request_id: Annotated[str | None, Header()] = None,
    session_id: Annotated[str | None, Cookie()] = None,
) -> ItemResponse:
    ...
```

- `Annotated[T, Metadata]` (Python 3.9+) separa tipo da vincoli
- `Path`, `Query`, `Header`, `Cookie`, `Body`, `Form`, `File` — tutti ereditano da `Param`
- Validazione automatica → `422 Unprocessable Entity` con dettagli

---

## Request Body con Pydantic

```python
from pydantic import BaseModel, Field, EmailStr, field_validator
from typing import Annotated
from datetime import datetime

class TaskCreate(BaseModel):
    title: Annotated[str, Field(min_length=1, max_length=200)]
    description: str | None = None
    priority: Priority = Priority.MEDIUM
    due_date: datetime | None = None
    tags: list[str] = Field(default_factory=list)

    @field_validator("title")
    @classmethod
    def title_not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Title cannot be blank")
        return v.strip()

class TaskResponse(TaskCreate):
    id: int
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)  # ORM mode
```

Uso in route:
```python
@app.post("/tasks", response_model=TaskResponse, status_code=201)
async def create_task(task: TaskCreate) -> TaskResponse:
    created = await service.create(task)
    return created
```

- `response_model` filtra e serializza l'output (esclude campi privati)
- `status_code` sovrascrive default (200 per GET, 201 per POST)

---

## Dependency Injection: Il Sistema più Potente di FastAPI

Le dependency sono funzioni (sync o async) che FastAPI chiama e inietta.

```python
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

# Dependency semplice
def get_settings() -> Settings:
    return Settings()

# Dependency con lifecycle (generator)
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSession(engine) as session:
        yield session

# Dependency che usa altre dependency
async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    payload = decode_token(token)
    user = await db.get(User, payload["sub"])
    if not user:
        raise HTTPException(401, "Invalid token")
    return user
```

Caratteristiche:
- **Caching per request**: stessa dependency chiamata più volte = eseguita una volta
- **Override per testing**: `app.dependency_overrides[get_db] = lambda: test_session`
- **Sub-dependency**: grafo arbitrario di dipendenze
- **Parametrizzazione**: `Depends(get_db, use_cache=False)`

---

## Router: Organizzazione Modulare

```python
# app/routers/tasks.py
from fastapi import APIRouter

router = APIRouter(prefix="/tasks", tags=["Tasks"])

@router.get("")
async def list_tasks(...) -> list[TaskResponse]: ...

@router.post("", status_code=201)
async def create_task(...) -> TaskResponse: ...

@router.get("/{task_id}")
async def get_task(task_id: int, ...) -> TaskResponse: ...

@router.patch("/{task_id}")
async def update_task(task_id: int, ...) -> TaskResponse: ...

@router.delete("/{task_id}", status_code=204)
async def delete_task(task_id: int, ...): ...
```

```python
# app/main.py
from app.routers import tasks, projects, users

app.include_router(tasks.router, prefix="/api/v1")
app.include_router(projects.router, prefix="/api/v1")
app.include_router(users.router, prefix="/api/v1")
```

- `prefix` evita ripetizione
- `tags` raggruppa in OpenAPI/Swagger
- Router annidabili: `router.include_router(sub_router, prefix="/sub")`

---

## Middleware: Cross-Cutting Concerns

```python
import time
import uuid
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        trace_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.trace_id = trace_id

        start = time.perf_counter()
        response = await call_next(request)
        duration = time.perf_counter() - start

        logger.info(
            "http_request",
            method=request.method,
            path=request.url.path,
            status=response.status_code,
            duration_ms=round(duration * 1000, 2),
            trace_id=trace_id,
        )
        response.headers["X-Request-ID"] = trace_id
        return response

app.add_middleware(RequestLoggingMiddleware)
```

Middleware built-in utili:
- `CORSMiddleware` — CORS
- `GZipMiddleware` — compressione response > 500 bytes
- `TrustedHostMiddleware` — protezione Host header
- `HTTPSRedirectMiddleware` — force HTTPS

---

## Error Handling: Coerenza Globale

```python
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError

class APIError(HTTPException):
    def __init__(self, status_code: int, code: str, detail: str, trace_id: str | None = None):
        super().__init__(status_code, detail)
        self.code = code
        self.trace_id = trace_id

@app.exception_handler(APIError)
async def api_error_handler(request: Request, exc: APIError):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "detail": exc.detail,
            "code": exc.code,
            "trace_id": exc.trace_id or request.state.trace_id,
        },
    )

@app.exception_handler(ValidationError)
async def validation_error_handler(request: Request, exc: ValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Validation failed",
            "code": "VALIDATION_ERROR",
            "errors": exc.errors(),
            "trace_id": request.state.trace_id,
        },
    )

@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception):
    logger.exception("unhandled_error", trace_id=request.state.trace_id)
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "code": "INTERNAL_ERROR",
            "trace_id": request.state.trace_id,
        },
    )
```

Uso:
```python
raise APIError(404, "NOT_FOUND", "Task not found")
```

---

## Background Tasks: Operazioni Non-Bloccanti

```python
from fastapi import BackgroundTasks

def send_email(to: str, subject: str, body: str) -> None:
    # SMTP call, potentially slow
    ...

@app.post("/tasks/{task_id}/remind", status_code=202)
async def schedule_reminder(
    task_id: int,
    background: BackgroundTasks,
    current_user: User = Depends(get_current_user),
):
    task = await service.get(task_id, current_user.id)
    background.add_task(send_email, current_user.email, f"Reminder: {task.title}", "...")
    return {"status": "queued"}
```

- Esegue **dopo** che la response è inviata
- Non garantisce esecuzione (se il processo crasha, task perso)
- Per affidabilità: **Celery + Redis/RabbitMQ** (Cap. 10)

---

## WebSocket: Comunicazione Bidirezionale

```python
from fastapi import WebSocket, WebSocketDisconnect
from collections import defaultdict

class ConnectionManager:
    def __init__(self):
        self.rooms: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, websocket: WebSocket, room: str):
        await websocket.accept()
        self.rooms[room].add(websocket)

    def disconnect(self, websocket: WebSocket, room: str):
        self.rooms[room].discard(websocket)

    async def broadcast(self, room: str, message: str):
        for ws in self.rooms[room].copy():
            try:
                await ws.send_text(message)
            except WebSocketDisconnect:
                self.disconnect(ws, room)

manager = ConnectionManager()

@app.websocket("/ws/{room}")
async def websocket_endpoint(websocket: WebSocket, room: str):
    await manager.connect(websocket, room)
    try:
        while True:
            data = await websocket.receive_text()
            await manager.broadcast(room, f"[{room}] {data}")
    except WebSocketDisconnect:
        manager.disconnect(websocket, room)
```

Per produzione: **Redis Pub/Sub** per scalare orizzontalmente (multi-instance).

---

## Struttura Progetto Consigliata

```
app/
├── main.py                 # App factory, middleware, exception handlers
├── core/
│   ├── config.py           # Settings (pydantic-settings)
│   ├── security.py         # Hash, JWT, OAuth2
│   ├── database.py         # Engine, session, base
│   └── logging.py          # Structlog config
├── models/
│   ├── user.py
│   ├── task.py
│   └── ...
├── schemas/
│   ├── user.py             # Pydantic models (request/response)
│   └── task.py
├── services/
│   ├── user_service.py     # Business logic
│   └── task_service.py
├── routers/
│   ├── users.py
│   ├── tasks.py
│   └── auth.py
├── dependencies/
│   └── auth.py             # get_current_user, require_role
└── tests/
    ├── conftest.py
    └── test_tasks.py
```

---

## Checklist Produzione FastAPI

- [ ] `app = FastAPI(..., docs_url=None, redoc_url=None)` in produzione (o dietro auth)
- [ ] `TRUSTED_HOST_MIDDLEWARE` configurato
- [ ] `GZipMiddleware` abilitato
- [ ] CORS: `allow_origins` espliciti, no `["*"]` in produzione
- [ ] Rate limiting su auth endpoints (`slowapi`)
- [ ] Request size limit (`middleware` o `nginx client_max_body_size`)
- [ ] Timeout configurato (`uvicorn --timeout-keep-alive`)
- [ ] OpenAPI schema versionato e pubblicato

---

## Glossario Capitolo 4

| Termine | Definizione |
|---------|-------------|
| **Dependency Injection** | Pattern: le dipendenze vengono fornite (iniettate) anziché create internamente |
| **ASGI** | Asynchronous Server Gateway Interface — standard Python per server async (successore WSGI) |
| **Starlette** | Toolkit ASGI su cui FastAPI è costruito (routing, middleware, WebSocket, static files) |
| **Uvicorn** | Server ASGI veloce, basato su uvloop + httptools |
| **OpenAPI** | Specifica per descrizione API REST (ex Swagger) |
| **BackgroundTasks** | FastAPI utility per eseguire funzioni dopo aver restituito la response |

---

## Prossimo Capitolo

Nel **Capitolo 5** connetteremo l'API a un database: SQLAlchemy 2.0 (async), modelli, relazioni, session management, migrazioni Alembic, e transizioni SQLite → PostgreSQL.