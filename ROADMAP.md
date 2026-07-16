# Roadmap: Backend/API Programming con Python

## 1. Python Fundamentals (da frontend a Python)
- Sintassi base: tipi, liste, dict, comprehensions, tuple, set
- Funzioni, *args/**kwargs, type hints
- Programmazione asincrona: `asyncio`, `async/await`
- Differenze mentali: Python è sync by default, batterie incluse, indentation-sensitive
- Gestione dipendenze: `pip`, `venv`, `pyproject.toml`, `uv` / `rye`

## 2. Fondamenti di Rete e HTTP
- TCP/IP, porte, DNS
- HTTP: metodi (GET/POST/PUT/PATCH/DELETE), status code, headers, body
- Statelessness, sessioni, cookies
- CORS (perché esiste e come gestirlo)

## 3. REST API Design
- Resource-oriented design: /users, /users/{id}, /users/{id}/posts
- CRUD mapping su HTTP methods
- HATEOAS (solo concettualmente)
- Versioning: /v1/, Accept header
- Best practice: naming plural, use nouns non verbs, nested resources con misura

## 4. Web Framework (consiglio: FastAPI)
- Routing, path/query params, request body
- Dependency injection
- Middleware
- Error handling, custom exceptions
- Background tasks
- WebSocket di base

## 5. Database & ORM
- SQL: SELECT, INSERT, UPDATE, DELETE, JOIN, GROUP BY, indici
- SQLAlchemy 2.0 (o SQLModel per FastAPI): modelli, sessioni, migrations (Alembic)
- Relazioni: 1:N, N:N, carichi eager vs lazy
- Connection pool, transactions
- NoSQL? Redis (cache), PostgreSQL JSONB (document store ibrido)

## 6. Autenticazione & Autorizzazione
- JWT: access + refresh token
- OAuth2: Authorization Code flow, PKCE
- Password hashing: bcrypt / argon2
- Role-based access control (RBAC)
- Rate limiting, API keys per servizio

## 7. Testing
- pytest: fixtures, conftest, parametrize
- httpx + `TestClient` per integration test
- Mocking: `unittest.mock`, `pytest-mock`
- Test DB: database temporaneo o in-memory

## 8. Deployment & DevOps
- Docker: Dockerfile multi-stage, docker-compose
- Environment variables, `.env`, pydantic-settings
- Process manager: gunicorn / uvicorn
- Reverse proxy: nginx / Caddy, TLS termination
- CI/CD: GitHub Actions (lint, test, build, deploy)

## 9. Monitoring & Observability
- Logging strutturato (structlog / loguru)
- OpenTelemetry: tracing + metrics
- Health check endpoint (/health, /ready)

## 10. Concetti Avanzati (dopo)
- Message queue: RabbitMQ / Redis Streams per task asincroni
- CQRS/Event Sourcing
- gRPC (microservizi interni)
- GraphQL (Strawberry / Ariadne)
- API Gateway, service discovery, circuit breaker

## Asset da frontend che porti con te
- Tipo forte / interfacce → Type hints + Pydantic
- Async mindset → `async def` in FastAPI
- Testing con mock → `pytest` + `unittest.mock`
- Docker già lo sai
- Debugging via `breakpoint()` è come `debugger;`

## Future
- GitHub Pages: pubblicare corso come sito statico (mdbook, Hugo, Jekyll)

## Progetti pratici (in ordine)
1. API CRUD con FastAPI + SQLite (nessun auth)
2. Aggiungi auth JWT + refresh token
3. Migra a PostgreSQL + Alembic
4. Aggiungi Docker + docker-compose
5. Aggiungi test suite completa
6. Aggiungi Redis per caching
7. Aggiungi Celery per task asincroni (email, upload)
8. Deploy su Railway / Fly.io / Hetzner

## Risorse consigliate
- **Libri**: "FastAPI" di Bill Lubanovic, "Architecture Patterns with Python"
- **Docs**: FastAPI docs (leggile tutte), SQLAlchemy 2.0 tutorial
- **Canali YouTube**: ArjanCodes, PyCon talks su production Python
