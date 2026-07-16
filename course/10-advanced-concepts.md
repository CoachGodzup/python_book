# Capitolo 10 — Pattern Avanzati per Scalare

## Quando Applicare Questi Pattern

Non servono all'inizio. Segnali che sei pronto:
- >3 microservizi con comunicazione complessa
- Operazioni >2s che bloccano request HTTP
- Letture >> Scritture (es. dashboard, report)
- Necessità audit trail completo / replay eventi
- Client mobile con banda limitata / query flessibili
- Team multipli che deployano indipendentemente

---

## 1. Message Queue: Celery + Redis/RabbitMQ

### Architettura
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   API       │────>│  Redis      │<────│  Worker     │
│   (Producer)│     │  (Broker)   │     │  (Consumer) │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Setup

```python
# app/core/celery.py
from celery import Celery
from app.core.config import get_settings

settings = get_settings()

celery = Celery(
    "taskmanager",
    broker=settings.CELERY_BROKER_URL,      # redis://redis:6379/1
    backend=settings.CELERY_RESULT_BACKEND, # redis://redis:6379/2
    include=["app.tasks"],
)

celery.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_acks_late=True,           # ACK dopo completamento (non prima)
    worker_prefetch_multiplier=1,  # Un task per worker alla volta
    task_reject_on_worker_lost=True,
    task_routes={
        "app.tasks.email.*": {"queue": "emails"},
        "app.tasks.report.*": {"queue": "reports"},
        "app.tasks.webhook.*": {"queue": "webhooks"},
    },
)
```

### Task Definizione

```python
# app/tasks/email.py
from app.core.celery import celery
from app.services.email import send_email

@celery.task(
    bind=True,
    autoretry_for=(Exception,),
    retry_backoff=True,          # Exponential backoff
    retry_backoff_max=600,       # Max 10 min
    retry_jitter=True,
    max_retries=5,
)
def send_task_reminder(self, user_email: str, task_title: str, task_id: str):
    send_email(
        to=user_email,
        subject=f"Reminder: {task_title}",
        template="task_reminder",
        context={"task_title": task_title, "task_url": f"{settings.FRONTEND_URL}/tasks/{task_id}"},
    )
```

### Chiamata da API

```python
@router.post("/tasks/{task_id}/remind", status_code=202)
async def schedule_reminder(task_id: UUID, current_user: User = Depends(get_current_user)):
    task = await service.get_task(task_id, current_user.id)
    send_task_reminder.delay(current_user.email, task.title, str(task_id))
    return {"status": "queued"}
```

### Worker Avvio
```bash
# Sviluppo
celery -A app.core.celery worker -l info -Q emails,reports,webhooks

# Produzione (systemd / docker / k8s)
celery -A app.core.celery worker \
    --concurrency=4 \
    --pool=prefork \
    --queues=emails,reports,webhooks \
    --loglevel=info \
    --max-tasks-per-child=1000
```

### Monitoraggio: Flower
```bash
pip install flower
celery -A app.core.celery flower --port=5555
# UI: http://localhost:5555
```

---

## 2. Caching Strategico: Redis

### Pattern: Cache-Aside (Lazy Loading)

```python
# app/services/cache.py
import redis.asyncio as redis
import json
from functools import wraps
from app.core.config import get_settings

settings = get_settings()
r = redis.from_url(settings.REDIS_URL, decode_responses=True)

async def get_cached(key: str):
    data = await r.get(key)
    if data:
        return json.loads(data)
    return None

async def set_cached(key: str, value: dict, ttl: int = 300):
    await r.setex(key, ttl, json.dumps(value, default=str))

async def invalidate(pattern: str):
    cursor = 0
    while True:
        cursor, keys = await r.scan(cursor, match=pattern, count=100)
        if keys:
            await r.delete(*keys)
        if cursor == 0:
            break
```

### Decorator per Endpoint Read-Heavy

```python
# app/decorators/cached.py
from functools import wraps
from app.services.cache import get_cached, set_cached

def cached(ttl: int = 300, key_prefix: str = "api"):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Genera chiave da parametri
            import hashlib
            key_data = f"{key_prefix}:{func.__module__}.{func.__name__}:{args}:{kwargs}"
            cache_key = hashlib.sha256(key_data.encode()).hexdigest()[:32]

            cached = await get_cached(cache_key)
            if cached is not None:
                return cached

            result = await func(*args, **kwargs)
            await set_cached(cache_key, result, ttl)
            return result
        return wrapper
    return decorator
```

### Uso

```python
@router.get("/tasks/stats")
@cached(ttl=60, key_prefix="stats")
async def get_task_stats(current_user: User = Depends(get_current_user)):
    return await service.compute_stats(current_user.id)
```

### Invalidazione Write-Through

```python
async def create_task(data: TaskCreate, user_id: UUID):
    task = await db.create(data, user_id)
    await invalidate(f"stats:api.services.task_service.compute_stats:{user_id}:*")
    await invalidate(f"api.tasks.list_tasks:{user_id}:*")
    return task
```

### Strategie TTL

| Dato | TTL | Invalidation |
|------|-----|--------------|
| Stats dashboard | 60s | Write-through su create/update/delete |
| User profile | 300s | Event-driven (profile.updated) |
| Public catalog | 3600s | Scheduled refresh + manual purge |
| Computed reports | 3600-86400s | Async rebuild trigger |

---

## 3. CQRS: Command Query Responsibility Segregation

### Principio
- **Command** (Write): `POST/PUT/PATCH/DELETE` → Model normalizzato, consistenza forte
- **Query** (Read): `GET` → Model denormalizzato, ottimizzato per lettura

### Implementazione Pratica (Database Separati o Schema)

```python
# Writer DB (Primary)
DATABASE_URL_WRITER = "postgresql+asyncpg://user:pass@primary/db"

# Reader DB (Replica)
DATABASE_URL_READER = "postgresql+asyncpg://user:pass@replica/db"

# Dependency separate
async def get_writer_db() -> AsyncGenerator[AsyncSession, None]:
    async with writer_session_maker() as session:
        yield session

async def get_reader_db() -> AsyncGenerator[AsyncSession, None]:
    async with reader_session_maker() as session:
        yield session
```

```python
@router.post("/tasks", status_code=201)
async def create_task(
    cmd: TaskCreate,
    db: AsyncSession = Depends(get_writer_db),  # Writer
    current_user: User = Depends(get_current_user),
):
    return await task_service.create(cmd, current_user.id, db)

@router.get("/tasks")
async def list_tasks(
    query: TaskListQuery = Depends(),
    db: AsyncSession = Depends(get_reader_db),  # Reader
    current_user: User = Depends(get_current_user),
):
    return await task_service.list(query, current_user.id, db)
```

### View Materializzate per Query Complesse

```sql
-- Materialized view per dashboard stats
CREATE MATERIALIZED VIEW mv_user_task_stats AS
SELECT
    u.id AS user_id,
    COUNT(t.id) FILTER (WHERE t.status = 'open') AS open_count,
    COUNT(t.id) FILTER (WHERE t.status = 'done') AS done_count,
    MAX(t.created_at) AS last_activity
FROM users u
LEFT JOIN tasks t ON t.owner_id = u.id
GROUP BY u.id;

CREATE UNIQUE INDEX ON mv_user_task_stats (user_id);

-- Refresh async (pg_cron o job)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_task_stats;
```

---

## 4. Event Sourcing

### Concetto
Non salvare *stato corrente*, ma *sequenza di eventi* che lo hanno prodotto.

```
State = fold(initial_state, [Event1, Event2, Event3, ...])
```

### Quando Usare
- Audit trail legale/compliance
- Temporal queries ("stato al 2024-01-15")
- Rebuild read models da zero
- Debugging: replay esatto

### Struttura Minima

```python
# app/models/events.py
from sqlalchemy import Enum as SQLEnum
import enum

class EventType(enum.StrEnum):
    TASK_CREATED = "task_created"
    TASK_UPDATED = "task_updated"
    TASK_DELETED = "task_deleted"
    TASK_ASSIGNED = "task_assigned"

class Event(Base):
    __tablename__ = "events"

    id: Mapped[UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    aggregate_id: Mapped[UUID] = mapped_column(UUID(as_uuid=True), index=True)  # Task ID
    aggregate_type: Mapped[str] = mapped_column(String(50), index=True)  # "Task"
    type: Mapped[EventType] = mapped_column(SQLEnum(EventType), index=True)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    metadata: Mapped[dict] = mapped_column(JSONB, default=dict)  # user_id, ip, correlation_id
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (Index("ix_events_aggregate_created", "aggregate_id", "created_at"),)
```

### Projection (Read Model Rebuild)

```python
# app/services/projections.py
async def project_task_events(events: list[Event]) -> TaskReadModel:
    state = TaskReadModel()
    for event in events:
        match event.type:
            case EventType.TASK_CREATED:
                state.id = event.aggregate_id
                state.title = event.payload["title"]
                state.status = event.payload["status"]
            case EventType.TASK_UPDATED:
                for k, v in event.payload.items():
                    setattr(state, k, v)
            case EventType.TASK_DELETED:
                state.deleted = True
    return state
```

### Snapshot (Performance)

```python
# Ogni N eventi, salva snapshot
SNAPSHOT_INTERVAL = 100

async def get_task_state(task_id: UUID) -> TaskReadModel:
    # 1. Trova snapshot più recente
    snapshot = await db.execute(
        select(Snapshot).where(Snapshot.aggregate_id == task_id)
        .order_by(Snapshot.version.desc()).limit(1)
    )
    # 2. Carica eventi successivi
    events = await db.execute(
        select(Event).where(
            Event.aggregate_id == task_id,
            Event.created_at > (snapshot.created_at if snapshot else datetime.min)
        ).order_by(Event.created_at)
    )
    # 3. Applica
    state = snapshot.data if snapshot else TaskReadModel()
    return project_task_events(events.scalars().all(), base=state)
```

---

## 5. gRPC: Comunicazione Interna

### Perché non REST interno?
- Schema contrattuale (protobuf)
- HTTP/2 multiplexing
- Streaming bidirezionale nativo
- Code generation multi-lingua

### Definizione Proto

```protobuf
// proto/task.proto
syntax = "proto3";

package taskmanager;

service TaskService {
  rpc GetTask(GetTaskRequest) returns (Task);
  rpc ListTasks(ListTasksRequest) returns (stream Task);  // Server streaming
  rpc CreateTask(CreateTaskRequest) returns (Task);
  rpc UpdateTask(UpdateTaskRequest) returns (Task);
  rpc DeleteTask(DeleteTaskRequest) returns (google.protobuf.Empty);
}

message Task {
  string id = 1;
  string title = 2;
  string description = 3;
  TaskStatus status = 4;
  Priority priority = 5;
  string owner_id = 6;
  string project_id = 7;
  google.protobuf.Timestamp created_at = 8;
  google.protobuf.Timestamp updated_at = 9;
}

enum TaskStatus { OPEN = 0; IN_PROGRESS = 1; DONE = 2; ARCHIVED = 3; }
enum Priority { LOW = 0; MEDIUM = 1; HIGH = 2; URGENT = 3; }
```

### Generazione e Server

```bash
pip install grpcio grpcio-tools
python -m grpc_tools.protoc --proto_path=proto --python_out=app/grpc --grpc_python_out=app/grpc proto/task.proto
```

```python
# app/grpc/task_servicer.py
from app.grpc import task_pb2, task_pb2_grpc
from app.services.task import TaskService

class TaskServicer(task_pb2_grpc.TaskServiceServicer):
    def __init__(self, task_service: TaskService):
        self.service = task_service

    async def GetTask(self, request, context):
        task = await self.service.get(UUID(request.id))
        if not task:
            context.abort(grpc.StatusCode.NOT_FOUND, "Task not found")
        return task_to_proto(task)

    async def ListTasks(self, request, context):
        async for task in self.service.list(owner_id=UUID(request.owner_id)):
            yield task_to_proto(task)

# app/main.py
import grpc
from app.grpc import task_pb2_grpc
from app.grpc.task_servicer import TaskServicer

grpc_server = grpc.aio.server()
task_pb2_grpc.add_TaskServiceServicer_to_server(TaskServicer(task_service), grpc_server)
grpc_server.add_insecure_port("[::]:50051")
await grpc_server.start()
```

### Client (Altro Servizio)

```python
# Service B chiama Task Service via gRPC
channel = grpc.aio.insecure_channel("task-service:50051")
stub = task_pb2_grpc.TaskServiceStub(channel)

task = await stub.GetTask(task_pb2.GetTaskRequest(id=task_id))
tasks = [t async for t in stub.ListTasks(task_pb2.ListTasksRequest(owner_id=user_id))]
```

---

## 6. GraphQL: Flessibilità Query

### Quando
- Client mobile: una query = un round-trip
- Frontend con requisiti variabili (dashboard personalizzabili)
- Aggregazione multi-risorsa

### Strawberry + FastAPI

```python
# app/graphql/schema.py
import strawberry
from strawberry.fastapi import GraphQLRouter
from app.services.task import TaskService
from app.dependencies import get_task_service

@strawberry.type
class TaskType:
    id: strawberry.ID
    title: str
    description: str | None
    status: str
    priority: str
    created_at: datetime

@strawberry.type
class Query:
    @strawberry.field
    async def tasks(
        self,
        info: strawberry.Info,
        status: str | None = None,
        priority: str | None = None,
        limit: int = 20,
        offset: int = 0,
    ) -> list[TaskType]:
        service: TaskService = info.context["task_service"]
        return await service.list(
            owner_id=info.context["current_user"].id,
            status=status,
            priority=priority,
            limit=limit,
            offset=offset,
        )

    @strawberry.field
    async def task(self, info: strawberry.Info, id: strawberry.ID) -> TaskType | None:
        service: TaskService = info.context["task_service"]
        return await service.get(UUID(id))

schema = strawberry.Schema(query=Query)
graphql_app = GraphQLRouter(schema, context_getter=get_context)

# app/main.py
app.include_router(graphql_app, prefix="/graphql")
```

### Query Client
```graphql
query MyTasks($status: String) {
  tasks(status: $status, limit: 10) {
    id
    title
    status
    priority
    createdAt
  }
}
```

---

## 7. API Gateway Pattern

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌──────────────────┐
│   API Gateway    │  (Kong, Traefik, AWS API Gateway, custom FastAPI)
│  - Auth          │
│  - Rate Limit    │
│  - Routing       │
│  - Transform     │
└────┬────┬────┬───┘
     ▼    ▼    ▼
┌──────┐┌──────┐┌──────┐
│Tasks ││ Users ││ Notif│
│ Svc  ││ Svc  ││ Svc  │
└──────┘└──────┘└──────┘
```

### Gateway Leggero (FastAPI)

```python
# gateway/main.py
from fastapi import FastAPI, Request, HTTPException
from httpx import AsyncClient

app = FastAPI(title="API Gateway")

SERVICES = {
    "tasks": "http://task-service:8000",
    "users": "http://user-service:8000",
    "notifications": "http://notification-service:8000",
}

client = AsyncClient(timeout=30.0)

@app.api_route("/api/v1/{service}/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def proxy(service: str, path: str, request: Request):
    if service not in SERVICES:
        raise HTTPException(404, "Service not found")

    # Auth validation centralizzata
    auth_header = request.headers.get("Authorization")
    if not auth_header:
        raise HTTPException(401, "Missing Authorization")

    # Forward
    url = f"{SERVICES[service]}/api/v1/{path}"
    resp = await client.request(
        method=request.method,
        url=url,
        headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
        content=await request.body(),
        params=request.query_params,
    )
    return Response(content=resp.content, status_code=resp.status_code, headers=resp.headers)
```

---

## 8. Idempotency Key: POST Sicuri

### Problema
Client riprova POST (timeout, 5xx) → risorse duplicate.

### Soluzione: Header `Idempotency-Key`

```python
# app/dependencies/idempotency.py
from fastapi import Header, HTTPException, Request
from app.services.cache import get_cached, set_cached

IDEMPOTENCY_TTL = 86400  # 24h

async def idempotency_key(
    request: Request,
    idempotency_key: str | None = Header(None, alias="Idempotency-Key"),
) -> str | None:
    if not idempotency_key:
        return None

    cache_key = f"idempotency:{idempotency_key}"
    cached = await get_cached(cache_key)
    if cached:
        # Restituisce response cached
        raise HTTPException(
            status_code=cached["status_code"],
            detail=cached["detail"],
            headers=cached.get("headers", {}),
        )
    return idempotency_key
```

```python
@router.post("/payments", status_code=201)
async def create_payment(
    payment: PaymentCreate,
    idem_key: str | None = Depends(idempotency_key),
    current_user: User = Depends(get_current_user),
):
    result = await payment_service.create(payment, current_user.id)

    if idem_key:
        await set_cached(f"idempotency:{idem_key}", {
            "status_code": 201,
            "detail": result,
            "headers": {"Location": f"/api/v1/payments/{result['id']}"},
        }, ttl=IDEMPOTENCY_TTL)

    return result
```

---

## 9. Circuit Breaker: Resilienza a Cascata

```python
# app/services/resilience.py
import pybreaker
from app.services.notifications import NotificationService

breaker = pybreaker.CircuitBreaker(
    fail_max=5,           # Apri dopo 5 fallimenti consecutivi
    reset_timeout=30,     # Tenta chiusura dopo 30s
    exclude=[asyncio.CancelledError],  # Non contare come fallimento
)

class ResilientNotificationService:
    def __init__(self, service: NotificationService):
        self.service = service

    @breaker
    async def send(self, *args, **kwargs):
        return await self.service.send(*args, **kwargs)

# Uso
@router.post("/notify")
async def notify(resilient: ResilientNotificationService = Depends(get_resilient_notification)):
    try:
        await resilient.send(...)
    except pybreaker.CircuitBreakerError:
        # Circuit aperto: fallback (log, queue per retry, response 503)
        await queue_for_later(...)
        return {"status": "queued"}
```

---

## 10. Feature Flags: Deploy ≠ Release

```python
# app/core/flags.py
import redis.asyncio as redis
from app.core.config import get_settings

settings = get_settings()
r = redis.from_url(settings.REDIS_URL)

async def is_enabled(flag: str, user_id: UUID | None = None) -> bool:
    # 1. Global flag
    global_val = await r.get(f"flag:{flag}:global")
    if global_val is not None:
        return global_val == "1"

    # 2. User-specific override
    if user_id:
        user_val = await r.get(f"flag:{flag}:user:{user_id}")
        if user_val is not None:
            return user_val == "1"

    # 3. Percentage rollout
    pct = await r.get(f"flag:{flag}:percentage")
    if pct and user_id:
        # Consistent hash per user
        import hashlib
        hash_val = int(hashlib.md5(f"{flag}:{user_id}".encode()).hexdigest(), 16)
        return (hash_val % 100) < int(pct)

    return False
```

```python
@router.get("/tasks")
async def list_tasks(
    current_user: User = Depends(get_current_user),
    flags: FeatureFlags = Depends(get_feature_flags),
):
    include_archived = await flags.is_enabled("archived_tasks", current_user.id)
    # ...
```

---

## Decision Matrix: Quale Pattern Scegliere?

| Problema | Pattern | Complessità |
|----------|---------|-------------|
| Task lenta (email, report) | Celery + Redis | Bassa |
| Letture frequenti, dati quasi statici | Redis Cache-Aside | Bassa |
| Letture >> Scritture, query complesse | CQRS + Read Replica | Media |
| Audit trail, temporal query, replay | Event Sourcing | Alta |
| Comunicazione servizio-servizio | gRPC | Media |
| Query flessibili, mobile, aggregazione | GraphQL | Media |
| Multi-servizio, auth centralizzata | API Gateway | Media |
| POST non idempotenti | Idempotency Key | Bassa |
| Dipendenza instabile esterna | Circuit Breaker | Bassa |
| Deploy sicuro, rollback istantaneo | Feature Flags | Bassa |

---

## Checklist Pattern Avanzati

- [ ] Celery: task idempotenti, `acks_late`, `max_retries`, dead letter queue
- [ ] Redis: TTL appropriati, invalidazione write-through, key naming convention
- [ ] CQRS: writer/reader separation, replica lag monitoring
- [ ] Event Sourcing: snapshot strategy, projection versioning, event schema evolution
- [ ] gRPC: protobuf versioning (`optional` fields), deadlines, retry policy
- [ ] GraphQL: query complexity limit, depth limit, persisted queries
- [ ] API Gateway: rate limit per tenant, request/response transformation, circuit breaker
- [ ] Idempotency: key generation client-side, TTL 24h, deduplication storage
- [ ] Circuit Breaker: fail_max, reset_timeout, fallback definito, metrics export
- [ ] Feature Flags: percentage rollout, user targeting, kill switch, audit log

---

## Glossario Capitolo 10

| Termine | Definizione |
|---------|-------------|
| **Celery** | Distributed task queue Python (broker: Redis/RabbitMQ, backend: Redis/DB) |
| **Cache-Aside** | Pattern: app controlla cache → se miss, legge DB → popola cache |
| **Write-Through** | Scrivi DB + invalida/aggiorna cache nella stessa transazione |
| **CQRS** | Separazione modelli Command (write) e Query (read) |
| **Event Sourcing** | Persistenza stato come sequenza eventi immutabili |
| **Projection** | Funzione `fold(events) → read_model` per ricostruire stato |
| **Snapshot** | Stato materiale a versione N per evitare replay completo |
| **gRPC** | RPC framework Google, HTTP/2 + Protobuf, codegen multi-lingua |
| **Protobuf** | Serializzazione binaria schema-driven (`.proto`) |
| **GraphQL** | Query language per API: client specifica esattamente dati necessari |
| **API Gateway** | Single entry point: routing, auth, rate limit, transformation |
| **Idempotency Key** | Client-generated key per rendere POST sicuro da retry |
| **Circuit Breaker** | Pattern: monitora fallimenti → apre circuito → fallback → half-open → chiudi |
| **Feature Flag** | Toggle runtime per funzionalità (targeting, percentage, kill switch) |

---

## Conclusione del Corso

Hai ora una roadmap completa per diventare **Backend Engineer Python production-ready**:

| Capitolo | Competenza Chiave |
|----------|-------------------|
| 1 | Python moderno: type hints, async, Pydantic, dataclass, pattern matching |
| 2 | HTTP/TCP, metodi, status code, header, CORS, cookie vs token, TLS |
| 3 | REST design: risorse, naming, paginazione, filtri, HATEOAS, versioning, errori RFC 7807 |
| 4 | FastAPI: routing, DI, Pydantic validation, middleware, background tasks, WebSocket |
| 5 | SQLAlchemy 2.0 async: modelli, relazioni, eager loading, transazioni, Alembic |
| 6 | Auth: bcrypt, JWT (access+refresh), RBAC, rate limit, OAuth2/OIDC |
| 7 | Testing: pytest, fixtures, factory, mock, parametrizzazione, coverage, TDD |
| 8 | Docker multi-stage, compose, nginx, Gunicorn, CI/CD, deploy Railway/Fly.io |
| 9 | Observability: structlog, OpenTelemetry, Prometheus, health check, alerting |
| 10 | Pattern scala: Celery, Redis cache, CQRS, Event Sourcing, gRPC, GraphQL, Gateway, Idempotency, Circuit Breaker, Feature Flags |

### Prossimi Passi Pratici

1. **Clona** il repo `taskmanager/` e implementa capitolo per capitolo
2. **Aggiungi** un feature per capitolo (es. Cap.1 → CLI; Cap.2 → HTTP server; Cap.3 → REST design)
3. **Scrivi test** prima del codice (TDD) per auth, tasks, projects
4. **Containerizza** e deploya su Railway (gratis per hobby)
5. **Aggiungi** observability: log JSON, trace ID, `/metrics`, dashboard Grafana
6. **Sperimenta** un pattern avanzato: Celery per email, Redis per cache, GraphQL per dashboard

### Risorse di Riferimento

- **FastAPI**: https://fastapi.tiangolo.com
- **SQLAlchemy 2.0**: https://docs.sqlalchemy.org/en/20
- **Pydantic v2**: https://docs.pydantic.dev
- **pytest**: https://docs.pytest.org
- **OpenTelemetry Python**: https://opentelemetry.io/docs/instrumentation/python
- **Celery**: https://docs.celeryq.dev
- **Strawberry GraphQL**: https://strawberry.rocks
- **Architecture Patterns**: *Enterprise Integration Patterns* (Hohpe/Woolf), *Building Microservices* (Newman)

---

**Buon coding.** La differenza tra junior e senior non è conoscere tutto, ma sapere *dove guardare*, *come testare*, e *quando fermarsi*.