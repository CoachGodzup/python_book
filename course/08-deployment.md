# Capitolo 8 — Deployment e DevOps: Docker, CI/CD, Produzione

## Obiettivo: Da Locale a Produzione Affidabile

Pipeline completa:
1. **Containerizza** → Docker multi-stage
2. **Orchestra** → docker-compose (dev) / Kubernetes (prod opzionale)
3. **Configura** → Environment variables + pydantic-settings
4. **Proxy** → Nginx: TLS, static files, rate limiting, buffering
5. **Automatizza** → GitHub Actions: lint, test, build, deploy
6. **Osserva** → Health check, logging, graceful shutdown

---

## Docker: Multi-Stage Build

```dockerfile
# Dockerfile
# ---- Stage 1: Builder ----
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# System deps per build (es. psycopg, lxml)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc libpq-dev && rm -rf /var/lib/apt/lists/*

# Installa dipendenze Python in venv isolato
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY pyproject.toml poetry.lock* ./
RUN pip install poetry && poetry install --only=main --no-interaction

# ---- Stage 2: Runtime ----
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH=/app

# Utente non-root
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copia venv da builder
COPY --from=builder /opt/venv /opt/venv

# Copia codice
COPY --chown=appuser:appuser . .

USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/health', timeout=2).raise_for_status()" || exit 1

EXPOSE 8000

CMD ["gunicorn", "app.main:app", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "--workers", "4", "--timeout", "120", "--access-logfile", "-", "--error-logfile", "-"]
```

### .dockerignore
```
__pycache__
*.pyc
.pytest_cache
.coverage
htmlcov
.tox
.venv
venv
.env
.git
.gitignore
README.md
docs
tests
*.log
```

---

## docker-compose: Sviluppo e CI

```yaml
# docker-compose.yml
version: "3.9"

services:
  api:
    build:
      context: .
      target: runtime
    ports:
      - "8000:8000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - ./app:/app/app  # Hot reload dev (solo per target dev)

  db:
    image: postgres:16-alpine
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
  redisdata:
```

### Override per Sviluppo (`docker-compose.override.yml`)
```yaml
version: "3.9"
services:
  api:
    build:
      target: builder  # Usa stage con poetry install --all
    command: uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
    volumes:
      - ./app:/app/app
      - ./pyproject.toml:/app/pyproject.toml
    environment:
      DEBUG: "true"
```

---

## Configurazione: pydantic-settings

```python
# app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache

class Settings(BaseSettings):
    # App
    APP_NAME: str = "TaskManager API"
    DEBUG: bool = False
    ENVIRONMENT: str = "development"  # development | staging | production

    # Database
    DATABASE_URL: str  # Required, no default

    # Redis
    REDIS_URL: str = "redis://redis:6379/0"

    # Security
    SECRET_KEY: str  # Required, ≥32 chars
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # CORS
    CORS_ORIGINS: list[str] = ["http://localhost:5173"]

    # Email (es. SendGrid, Resend, SMTP)
    SMTP_HOST: str | None = None
    SMTP_PORT: int = 587
    SMTP_USER: str | None = None
    SMTP_PASSWORD: str | None = None
    EMAIL_FROM: str = "noreply@example.com"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

@lru_cache
def get_settings() -> Settings:
    return Settings()
```

### .env.example (commitato)
```bash
APP_NAME="TaskManager API"
DEBUG=true
ENVIRONMENT=development
DATABASE_URL=postgresql+asyncpg://postgres:postgres@db:5432/taskmanager
REDIS_URL=redis://redis:6379/0
SECRET_KEY=dev-secret-key-change-in-production-min-32-chars
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30
CORS_ORIGINS=["http://localhost:5173","http://localhost:3000"]
```

---

## Entrypoint: Migrazioni + Avvio

```bash
#!/bin/bash
# docker/entrypoint.sh
set -e

echo "Waiting for database..."
until pg_isready -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME"; do
  sleep 1
done

echo "Running migrations..."
alembic upgrade head

echo "Starting server..."
exec "$@"
```

```dockerfile
# In Dockerfile runtime stage
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

---

## Gunicorn + Uvicorn Workers

```bash
# Produzione
gunicorn app.main:app \
    -k uvicorn.workers.UvicornWorker \
    --workers 4 \
    --bind 0.0.0.0:8000 \
    --timeout 120 \
    --keep-alive 5 \
    --max-requests 1000 \
    --max-requests-jitter 50 \
    --access-logfile - \
    --error-logfile - \
    --log-level info
```

- `--workers`: 2×CPU cores (es. 4 core → 4-8 workers)
- `--max-requests`: Ricicla worker per evitare memory leak
- `--timeout`: Kill worker bloccato > 120s

---

## Nginx Reverse Proxy

```nginx
# nginx/nginx.conf
upstream api {
    server api:8000;
    keepalive 32;
}

server {
    listen 80;
    server_name api.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Security headers
    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header Content-Security-Policy "default-src 'self'; frame-ancestors 'none';";

    # Rate limiting zone
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

    location / {
        limit_req zone=api_limit burst=20 nodelay;

        proxy_pass http://api;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Request-ID $request_id;

        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }

    location /health {
        proxy_pass http://api;
        access_log off;
    }
}
```

---

## GitHub Actions CI/CD

```yaml
# .github/workflows/ci.yml
name: CI/CD

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - name: Cache pip
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('poetry.lock') }}
      - run: pip install poetry
      - run: poetry install --with test,lint
      - run: poetry run ruff check .
      - run: poetry run pyright
      - run: poetry run pytest --cov=app --cov-fail-under=85

  build-and-push:
    needs: lint-and-test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Railway
        uses: railwayapp/railway-deploy@v1
        with:
          token: ${{ secrets.RAILWAY_TOKEN }}
          service: api
```

---

## Deploy: Railway / Fly.io / Render

### Railway (Più Semplice)
1. `railway login`
2. `railway init` → seleziona repo GitHub
3. Aggiungi `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY` in Variables
4. `railway up` o push su `main` → auto-deploy

### Fly.io (Edge, Più Controllo)
```toml
# fly.toml
app = "taskmanager-api"
primary_region = "fra"

[build]
  dockerfile = "Dockerfile"

[env]
  ENVIRONMENT = "production"

[http_service]
  internal_port = 8000
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

[[vm]]
  cpu_kind = "shared"
  cpus = 1
  memory_mb = 512
```
```bash
fly launch --copy-config
fly secrets set SECRET_KEY=... DATABASE_URL=... REDIS_URL=...
fly deploy
```

---

## Graceful Shutdown

```python
# app/main.py
import signal
import asyncio
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting up...")
    yield
    # Shutdown
    logger.info("Shutting down...")
    # Chiudi pool DB, Redis, cancella task in corso
    await engine.dispose()
    await redis.close()

app = FastAPI(lifespan=lifespan)

# Signal handling (Gunicorn gestisce SIGTERM, ma utile per uvicorn standalone)
def handle_sigterm(*_):
    raise KeyboardInterrupt()

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)
```

---

## Checklist Produzione

- [ ] Docker multi-stage build (< 150MB final image)
- [ ] Non-root user in container
- [ ] Health check endpoint (`/health`) + Docker HEALTHCHECK
- [ ] `pydantic-settings` per config, `.env` solo dev
- [ ] `SECRET_KEY` ≥ 32 byte random, solo secret manager
- [ ] PostgreSQL + asyncpg, connection pool sizing
- [ ] Redis per cache/session/rate-limit
- [ ] Nginx: TLS 1.3, security headers, rate limiting, buffering
- [ ] Gunicorn + UvicornWorker, workers = 2×CPU
- [ ] Graceful shutdown: `engine.dispose()`, chiudi Redis, flush log
- [ ] CI: lint → type-check → test → build → deploy
- [ ] Deploy: zero-downtime (rolling update), rollback < 1 min
- [ ] Monitoring: `/metrics` (Prometheus), `/health` (LB), log JSON
- [ ] Backup DB: automated, testato, point-in-time recovery

---

## Glossario Capitolo 8

| Termine | Definizione |
|---------|-------------|
| **Multi-stage build** | Dockerfile con stage separati (builder → runtime) per immagini minimali |
| **ASGI** | Asynchronous Server Gateway Interface — standard Python per server async |
| **Gunicorn** | Process manager WSGI/ASGI: master + worker processes |
| **UvicornWorker** | Worker Gunicorn che usa Uvicorn (async) per gestire request |
| **Reverse Proxy** | Server che riceve request esterne e le inoltra a backend interni |
| **Rate Limiting** | Controllo frequenza request per IP/utente (token bucket, leaky bucket) |
| **Graceful Shutdown** | Chiusura ordinata: stop accepting → finish in-flight → cleanup → exit |
| **Rolling Update** | Deploy incrementale: nuovo pod/container up → health check → vecchio down |
| **Secret Manager** | Servizio gestione segreti (AWS Secrets Manager, HashiCorp Vault, 1Password, Railway Variables) |

---

## Prossimo Capitolo

Nel **Capitolo 9** implementeremo observability completa: structured logging (structlog), distributed tracing (OpenTelemetry), metrics (Prometheus), health checks, alerting, e correlazione log-trace-metric via `trace_id`.