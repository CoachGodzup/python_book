# Capitolo 9 — Monitoring, Logging, e Observability

## I Tre Pilastri

| Pilastro | Domanda | Tooling |
|----------|---------|---------|
| **Logs** | Cosa è successo? (eventi discreti) | `structlog` → JSON → Loki / Elasticsearch |
| **Metrics** | Quanto/quanto spesso? (aggregati) | Prometheus client → Prometheus → Grafana |
| **Traces** | Dove ha passato tempo la request? | OpenTelemetry → Jaeger / Tempo / Zipkin |

Correlazione: **`trace_id`** presente in log, metriche (exemplars), e trace.

---

## Structured Logging con `structlog`

```python
# app/core/logging.py
import structlog
from structlog.types import EventDict
from app.core.config import get_settings

def add_trace_id(logger, method_name: str, event_dict: EventDict) -> EventDict:
    from contextvars import ContextVar
    trace_id: ContextVar[str] = ContextVar("trace_id", default="")
    if tid := trace_id.get():
        event_dict["trace_id"] = tid
    return event_dict

def setup_logging():
    settings = get_settings()
    shared_processors = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        add_trace_id,
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]

    if settings.ENVIRONMENT == "development":
        processors = shared_processors + [
            structlog.dev.ConsoleRenderer(colors=True),
        ]
    else:
        processors = shared_processors + [
            structlog.processors.dict_tracebacks,
            structlog.processors.JSONRenderer(),
        ]

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.stdlib.BoundLogger,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )
```

### Middleware Trace ID

```python
# app/middleware/tracing.py
import uuid
from contextvars import ContextVar
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

trace_id_var: ContextVar[str] = ContextVar("trace_id", default="")

class TraceIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        trace_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        trace_id_var.set(trace_id)
        request.state.trace_id = trace_id

        with structlog.contextvars.bound_contextvars(trace_id=trace_id):
            response = await call_next(request)

        response.headers["X-Request-ID"] = trace_id
        return response
```

### Uso nei Log

```python
# app/services/task_service.py
import structlog
logger = structlog.get_logger(__name__)

async def create_task(db, user, data):
    logger.info("task_creation_started", user_id=str(user.id), title=data.title)
    try:
        task = await _create(db, user, data)
        logger.info("task_created", task_id=str(task.id), user_id=str(user.id))
        return task
    except Exception as e:
        logger.exception("task_creation_failed", user_id=str(user.id), error=str(e))
        raise
```

Output produzione (JSON):
```json
{"timestamp":"2025-07-16T10:30:00.123Z","level":"info","event":"task_created","task_id":"550e8400-e29b","user_id":"123e4567-e89b","trace_id":"a1b2c3d4","logger":"app.services.task_service"}
```

---

## OpenTelemetry: Distributed Tracing

```python
# app/core/telemetry.py
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

def setup_telemetry(app: FastAPI, settings):
    if not settings.OTEL_EXPORTER_OTLP_ENDPOINT:
        return

    provider = TracerProvider()
    processor = BatchSpanProcessor(
        OTLPSpanExporter(endpoint=settings.OTEL_EXPORTER_OTLP_ENDPOINT, insecure=True)
    )
    provider.add_span_processor(processor)
    trace.set_tracer_provider(provider)

    # Auto-instrumentation
    FastAPIInstrumentor.instrument_app(app, tracer_provider=provider)
    SQLAlchemyInstrumentor().instrument(engine=engine, tracer_provider=provider)
    RedisInstrumentor().instrument(tracer_provider=provider)
    HTTPXClientInstrumentor().instrument(tracer_provider=provider)
```

### Span Custom per Business Logic

```python
# app/services/task_service.py
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

async def create_task(db, user, data):
    with tracer.start_as_current_span("create_task") as span:
        span.set_attribute("user.id", str(user.id))
        span.set_attribute("task.title", data.title)
        span.set_attribute("task.priority", data.priority.value)

        task = await _create(db, user, data)

        span.set_attribute("task.id", str(task.id))
        return task
```

---

## Prometheus Metrics

```python
# app/core/metrics.py
from prometheus_client import Counter, Histogram, Gauge, Info
from prometheus_fastapi_instrumentator import Instrumentator

# Custom metrics
TASKS_CREATED = Counter("tasks_created_total", "Total tasks created", ["priority", "status"])
TASK_OPERATION_DURATION = Histogram(
    "task_operation_duration_seconds",
    "Task operation latency",
    ["operation", "status"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)
ACTIVE_USERS = Gauge("active_users", "Currently authenticated users")
APP_INFO = Info("app_info", "Application metadata")

def init_metrics(app: FastAPI):
    Instrumentator(
        should_group_status_codes=True,
        should_ignore_untemplated=True,
        should_respect_env_var=True,
        excluded_handlers=["/health", "/metrics"],
    ).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)

    APP_INFO.info({"version": "1.0.0", "environment": settings.ENVIRONMENT})
```

### Uso in Service

```python
import time
from app.core.metrics import TASKS_CREATED, TASK_OPERATION_DURATION

async def create_task(db, user, data):
    start = time.perf_counter()
    try:
        task = await _create(db, user, data)
        TASKS_CREATED.labels(priority=data.priority.value, status="success").inc()
        return task
    except Exception:
        TASKS_CREATED.labels(priority=data.priority.value, status="error").inc()
        raise
    finally:
        TASK_OPERATION_DURATION.labels(operation="create", status="all").observe(time.perf_counter() - start)
```

### Metriche Esportate (esempi)

```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="POST",path="/api/v1/tasks",status="201"} 1423

# HELP task_operation_duration_seconds Task operation latency
# TYPE task_operation_duration_seconds histogram
task_operation_duration_seconds_bucket{operation="create",status="all",le="0.1"} 1380
task_operation_duration_seconds_bucket{operation="create",status="all",le="0.5"} 1410
```

---

## Health Checks: Liveness vs Readiness

```python
# app/routers/health.py
from fastapi import APIRouter, Depends, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
import redis.asyncio as redis
from app.core.database import get_db
from app.core.config import get_settings

router = APIRouter(tags=["Health"])

@router.get("/health/live", status_code=status.HTTP_200_OK)
async def liveness():
    """Kubernetes liveness probe: processo vivo?"""
    return {"status": "alive"}

@router.get("/health/ready", status_code=status.HTTP_200_OK)
async def readiness(
    db: AsyncSession = Depends(get_db),
    settings = Depends(get_settings),
):
    """Kubernetes readiness probe: pronto a servire traffico?"""
    checks = {}

    # DB
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as e:
        checks["database"] = f"error: {e}"

    # Redis
    try:
        r = redis.from_url(settings.REDIS_URL)
        await r.ping()
        await r.close()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = f"error: {e}"

    all_ok = all(v == "ok" for v in checks.values())
    return {
        "status": "ready" if all_ok else "degraded",
        "checks": checks,
    }
```

### Docker Healthcheck
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health/ready || exit 1
```

### Kubernetes Probe
```yaml
livenessProbe:
  httpGet: { path: /health/live, port: 8000 }
  initialDelaySeconds: 10
  periodSeconds: 30
readinessProbe:
  httpGet: { path: /health/ready, port: 8000 }
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
```

---

## Error Handling Globale con Trace ID

```python
# app/main.py
from fastapi import Request, FastAPI
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
import structlog

logger = structlog.get_logger(__name__)

def register_exception_handlers(app: FastAPI):
    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(request: Request, exc: StarletteHTTPException):
        trace_id = getattr(request.state, "trace_id", "unknown")
        logger.warning("http_exception",
            trace_id=trace_id,
            path=request.url.path,
            method=request.method,
            status_code=exc.status_code,
            detail=exc.detail,
        )
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "detail": exc.detail,
                "code": "HTTP_ERROR",
                "trace_id": trace_id,
            },
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        trace_id = getattr(request.state, "trace_id", "unknown")
        logger.warning("validation_error",
            trace_id=trace_id,
            path=request.url.path,
            errors=exc.errors(),
        )
        return JSONResponse(
            status_code=422,
            content={
                "detail": "Validation failed",
                "code": "VALIDATION_ERROR",
                "errors": exc.errors(),
                "trace_id": trace_id,
            },
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        trace_id = getattr(request.state, "trace_id", "unknown")
        logger.exception("unhandled_exception",
            trace_id=trace_id,
            path=request.url.path,
            method=request.method,
            error=str(exc),
        )
        return JSONResponse(
            status_code=500,
            content={
                "detail": "Internal server error",
                "code": "INTERNAL_ERROR",
                "trace_id": trace_id,
            },
        )
```

---

## Alerting: Regole Prometheus (Esempi)

```yaml
# prometheus/rules/alerts.yml
groups:
- name: api-alerts
  interval: 30s
  rules:
  - alert: HighErrorRate
    expr: |
      sum(rate(http_requests_total{status=~"5.."}[5m])) 
      / sum(rate(http_requests_total[5m])) > 0.02
    for: 5m
    labels: { severity: critical }
    annotations:
      summary: "Error rate > 2% for 5m"
      description: "{{ $value | humanizePercentage }} of requests are 5xx"

  - alert: HighLatencyP99
    expr: |
      histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, handler)) > 2
    for: 5m
    labels: { severity: warning }
    annotations:
      summary: "P99 latency > 2s"

  - alert: DatabaseDown
    expr: up{job="postgres"} == 0
    for: 1m
    labels: { severity: critical }
    annotations:
      summary: "PostgreSQL exporter down"

  - alert: HighMemoryUsage
    expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.85
    for: 10m
    labels: { severity: warning }
    annotations:
      summary: "Container memory > 85%"
```

---

## Correlazione Log-Metric-Trace

| Componente | Come Correlare |
|------------|----------------|
| **Log → Trace** | `trace_id` in ogni log entry (middleware + `structlog.contextvars`) |
| **Metric → Trace** | Prometheus **Exemplars**: `trace_id` allegato a campioni histogram |
| **Trace → Log** | Tempo span → filtra log per `trace_id` + timestamp range |

```python
# Esempio exemplar (richiede Prometheus client ≥ 0.17)
from prometheus_client import Histogram
H = Histogram("my_latency", "Latency", exemplars=True)

with H.time():
    # OpenTelemetry imposta automaticamente exemplar se span attivo
    pass
```

---

## Checklist Observability

- [ ] `structlog` configurato: JSON in prod, pretty in dev
- [ ] Middleware `trace_id` su ogni request/response
- [ ] `trace_id` in log, response header `X-Request-ID`
- [ ] OpenTelemetry auto-instrument: FastAPI, SQLAlchemy, Redis, HTTPX
- [ ] Span custom per operazioni business critiche
- [ ] `/metrics` Prometheus esposto (no auth, interno)
- [ ] Metriche custom: business (tasks_created), latency per operation, error rate
- [ ] Health endpoints: `/health/live` (liveness), `/health/ready` (readiness + deps)
- [ ] Docker HEALTHCHECK + K8s liveness/readiness probes
- [ ] Global exception handler: log `trace_id`, response RFC 7807
- [ ] Alerting: error rate, latency p99, saturation, DB/Redis down
- [ ] Log retention: 30gg hot, 1anno cold (compliance)
- [ ] Dashboard Grafana: RED metrics (Rate, Errors, Duration) per endpoint

---

## Glossario Capitolo 9

| Termine | Definizione |
|---------|-------------|
| **Observability** | Capacità di capire stato interno da output esterni (log, metriche, trace) |
| **Structured Logging** | Log come oggetti strutturati (JSON) non stringhe libere |
| **Trace ID** | Identificativo univoco per request end-to-end (W3C TraceContext standard) |
| **Span** | Unità di lavoro in un trace (operazione, DB query, HTTP call) |
| **Exemplar** | Valore metrica arricchito con `trace_id` per saltare da metrica a trace |
| **RED Metrics** | Rate (request/sec), Errors (error rate), Duration (latency) |
| **Liveness Probe** | "Il processo è vivo?" → restart se fallisce |
| **Readiness Probe** | "Pronto a servire traffico?" → rimuovi da LB se fallisce |
| **W3C TraceContext** | Standard `traceparent` / `tracestate` header per propagazione trace |

---

## Prossimo Capitolo

Nel **Capitolo 10** esploreremo pattern avanzati per scalare: message queue (Celery), caching (Redis), CQRS, Event Sourcing, gRPC, GraphQL, API Gateway, idempotency key, circuit breaker, feature flags.