# Glossario Completo: Backend API con Python

Riferimento unificato per tutti i 10 capitoli. Ogni termine include definizione concisa, capitolo di riferimento, e link alla specifica/risorsa autorevole.

---

## A

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **ABAC** | Attribute-Based Access Control: policy basate su attributi (utente, risorsa, ambiente) | 6 | [NIST SP 800-162](https://csrc.nist.gov/publications/detail/sp/800-162/final) |
| **ALPN** | Application-Layer Protocol Negotiation: estensione TLS per negoziare HTTP/2 | 2 | [RFC 7301](https://tools.ietf.org/html/rfc7301) |
| **Annotated** | `typing.Annotated[T, Metadata]`: separa tipo da metadati (Python 3.9+) | 1 | [PEP 593](https://peps.python.org/pep-0593/) |
| **ASGI** | Asynchronous Server Gateway Interface: standard per server/app async Python | 4 | [ASGI Spec](https://asgi.readthedocs.io/en/latest/specs/main.html) |
| **Auto-instrumentation** | OpenTelemetry: patch automatico librerie (FastAPI, SQLAlchemy, Redis, HTTPX) | 9 | [OTel Python](https://opentelemetry.io/docs/instrumentation/python/automatic/) |

## B

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Backpressure** | Meccanismo per rallentare producer quando consumer è lento | 10 | [Reactive Streams](https://www.reactive-streams.org/) |
| **Bcrypt** | Funzione hash per password con work factor configurabile (default 12) | 6 | [bcrypt](https://bcrypt.online/) |
| **Broker** | Message queue intermediario (Redis, RabbitMQ, Kafka) | 10 | [Celery Brokers](https://docs.celeryq.dev/en/stable/getting-started/brokers/) |

## C

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Cache-Aside** | Pattern: app controlla cache → se miss, legge DB → popola cache | 10 | [Cloud Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/patterns/cache-aside) |
| **Circuit Breaker** | Pattern: dopo N fallimenti, "apre" e fail-fast per timeout | 10 | [Martin Fowler](https://martinfowler.com/bliki/CircuitBreaker.html) |
| **CORS** | Cross-Origin Resource Sharing: header per permettere richieste cross-origin | 2 | [MDN CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) |
| **CQRS** | Command Query Responsibility Segregation: separa modello scrittura da lettura | 10 | [Martin Fowler](https://martinfowler.com/bliki/CQRS.html) |
| **CSRF** | Cross-Site Request Forgery: attacco che forza utente autenticato a inviare richiesta | 6 | [OWASP CSRF](https://owasp.org/www-community/attacks/csrf) |

## D

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Dataclass** | `@dataclass`: genera `__init__`, `__repr__`, `__eq__` per classi dati | 1 | [PEP 557](https://peps.python.org/pep-0557/) |
| **Dependency Injection** | Pattern: dipendenze fornite esternamente (non create internamente) | 4 | [Martin Fowler](https://martinfowler.com/articles/injection.html) |
| **Dialect** | Adattatore SQLAlchemy per specifico DB (postgresql, mysql, sqlite) | 5 | [SQLAlchemy Dialects](https://docs.sqlalchemy.org/en/20/core/engines.html#database-urls) |

## E

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Eager Loading** | Caricamento proattivo relazioni (`selectinload`, `joinedload`) per evitare N+1 | 5 | [SQLAlchemy Loading](https://docs.sqlalchemy.org/en/20/orm/loading_relationships.html) |
| **Event Sourcing** | Salva sequenza eventi (non stato) → stato = fold(eventi) | 10 | [Martin Fowler](https://martinfowler.com/eaaDev/EventSourcing.html) |
| **Exemplar** | Valore metrica Prometheus arricchito con `trace_id` per correlazione | 9 | [Prometheus Exemplars](https://prometheus.io/docs/concepts/exemplars/) |

## F

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **FastAPI** | Framework API moderno, type-hint native, OpenAPI auto, async, basato su Starlette | 4 | [FastAPI Docs](https://fastapi.tiangolo.com/) |
| **Fixture** | Funzione pytest che prepara/teardown contesto condiviso (DB, client, user) | 7 | [pytest Fixtures](https://docs.pytest.org/en/stable/fixture.html) |
| **Foreign Key** | Colonna che referencia PK di altra tabella (integrità referenziale) | 5 | [PostgreSQL FK](https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK) |

## G

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Gunicorn** | Process manager WSGI/ASGI: master + worker processes | 8 | [Gunicorn](https://gunicorn.org/) |
| **GraphQL** | Query language per API: client specifica esattamente dati necessari | 10 | [GraphQL Spec](https://spec.graphql.org/) |

## H

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **HATEOAS** | Hypermedia as the Engine of Application State: link in response per navigazione | 3 | [Richardson Maturity Model](https://martinfowler.com/articles/richardsonMaturityModel.html) |
| **Health Check** | Endpoint per verificare stato servizio (liveness/readiness) | 8, 9 | [Kubernetes Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |
| **HMAC** | Hash-based Message Authentication Code: integrità + autenticità con chiave segreta | 6 | [RFC 2104](https://tools.ietf.org/html/rfc2104) |
| **HTTP/2** | Binary, multiplexed, header compression (HPACK), server push | 2 | [RFC 7540](https://tools.ietf.org/html/rfc7540) |
| **HTTP/3** | QUIC (UDP), 0-RTT, no head-of-line blocking | 2 | [RFC 9114](https://tools.ietf.org/html/rfc9114) |

## I

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Idempotency Key** | Client-generato: rende POST idempotente (stessa chiave = stessa risposta) | 10 | [Stripe Idempotency](https://stripe.com/docs/api/idempotent_requests) |
| **Identity Map** | Cache in-session: stesso PK = stessa istanza Python (SQLAlchemy) | 5 | [SQLAlchemy Identity Map](https://docs.sqlalchemy.org/en/20/orm/session_basics.html#identity-map) |
| **JWT** | JSON Web Token: token compatto, auto-contenuto, firmato (JWS) o cifrato (JWE) | 6 | [RFC 7519](https://tools.ietf.org/html/rfc7519) |

## L

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Lazy Loading** | Caricamento relazione al primo accesso (rischio N+1) | 5 | [SQLAlchemy Lazy](https://docs.sqlalchemy.org/en/20/orm/loading_relationships.html#lazy-loading) |
| **Liveness Probe** | "Processo vivo?" → restart container se fallisce | 8, 9 | [K8s Liveness](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |

## M

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Middleware** | Codice che intercetta request/response prima/dopo route handler | 4 | [Starlette Middleware](https://www.starlette.io/middleware/) |
| **Migration** | Script versionato per evolvere schema DB (Alembic) | 5 | [Alembic](https://alembic.sqlalchemy.org/en/latest/) |
| **Mock** | Sostituisce dipendenza con oggetto controllato per test isolati | 7 | [unittest.mock](https://docs.python.org/3/library/unittest.mock.html) |
| **MVCC** | Multi-Version Concurrency Control: letture non bloccanti (PostgreSQL) | 5 | [PostgreSQL MVCC](https://www.postgresql.org/docs/current/mvcc.html) |

## N

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **N+1 Problem** | 1 query parent + N query children = N+1 roundtrip DB | 5 | [SQLAlchemy N+1](https://docs.sqlalchemy.org/en/20/orm/loading_relationships.html#the-n-plus-one-problem) |

## O

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **OIDC** | OpenID Connect: strato identità su OAuth2 (standardizza `userinfo`, `id_token`) | 6 | [OIDC Spec](https://openid.net/specs/openid-connect-core-1_0.html) |
| **OpenTelemetry** | Standard vendor-neutral per traces, metrics, logs | 9 | [OTel](https://opentelemetry.io/) |
| **ORM** | Object-Relational Mapping: mapping classi Python ↔ tabelle relazionali | 5 | [SQLAlchemy ORM](https://docs.sqlalchemy.org/en/20/orm/) |

## P

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Parametrizazione** | `@pytest.mark.parametrize`: esegue stesso test con input/expected multipli | 7 | [pytest Parametrize](https://docs.pytest.org/en/stable/parametrize.html) |
| **PKCE** | Proof Key for Code Exchange: estensione OAuth2 per prevenire auth code interception | 6 | [RFC 7636](https://tools.ietf.org/html/rfc7636) |
| **Pool** | Cache connessioni DB riutilizzabili (evita handshake ripetuto) | 5 | [SQLAlchemy Pool](https://docs.sqlalchemy.org/en/20/core/pooling.html) |
| **Problem Details** | RFC 7807: formato standard errori HTTP (`type`, `title`, `status`, `detail`, `instance`) | 3 | [RFC 7807](https://tools.ietf.org/html/rfc7807) |
| **Protocol** | `typing.Protocol`: structural subtyping (duck typing statico) | 1 | [PEP 544](https://peps.python.org/pep-0544/) |
| **Pydantic** | Validazione dati + serializzazione usando type hints (core di FastAPI) | 1, 4 | [Pydantic Docs](https://docs.pydantic.dev/) |

## Q

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **QUIC** | UDP-based transport: HTTP/3, 0-RTT, connection migration | 2 | [RFC 9000](https://tools.ietf.org/html/rfc9000) |

## R

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Rate Limiting** | Controllo frequenza request per IP/utente (token bucket, sliding window) | 6, 8 | [SlowAPI](https://github.com/laurents/slowapi) |
| **RBAC** | Role-Based Access Control: permessi assegnati a ruoli, ruoli a utenti | 6 | [NIST RBAC](https://csrc.nist.gov/projects/role-based-access-control) |
| **Readiness Probe** | "Pronto a servire traffico?" → rimuovi da LB se fallisce | 8, 9 | [K8s Readiness](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) |
| **Refresh Token** | Token lunga durata (7-30gg) per ottenere nuovo access token senza re-login | 6 | [OAuth2 Refresh](https://tools.ietf.org/html/rfc6749#section-6) |
| **Reverse Proxy** | Server che riceve request esterne e le inoltra a backend interni | 8 | [Nginx Reverse Proxy](https://nginx.org/en/docs/http/ngx_http_proxy_module.html) |
| **Rolling Update** | Deploy incrementale: nuovo pod up → health check → vecchio down | 8 | [K8s Rolling Update](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-update) |

## S

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Safe Method** | HTTP method che non modifica stato server (GET, HEAD, OPTIONS, TRACE) | 2 | [RFC 7231 §4.2.1](https://tools.ietf.org/html/rfc7231#section-4.2.1) |
| **Savepoint** | Punto di rollback parziale dentro transazione (nested transaction) | 5 | [PostgreSQL Savepoint](https://www.postgresql.org/docs/current/sql-savepoint.html) |
| **Span** | Unità di lavoro in un trace (operazione, DB query, HTTP call) | 9 | [OTel Span](https://opentelemetry.io/docs/concepts/signals/traces/#spans) |
| **SQLAlchemy** | ORM + Core Python: type-safe, async, mature, flessibile | 5 | [SQLAlchemy 2.0](https://docs.sqlalchemy.org/en/20/) |
| **Structured Logging** | Log come oggetti (JSON) non stringhe: queryable, correlabile | 9 | [structlog](https://www.structlog.org/) |

## T

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **TDD** | Test-Driven Development: Red (test fallisce) → Green (passa) → Refactor | 7 | [Kent Beck](https://testdriven.io/blog/tdd/) |
| **TLS** | Transport Layer Security: cifratura, integrità, autenticazione su TCP | 2 | [RFC 8446](https://tools.ietf.org/html/rfc8446) (TLS 1.3) |
| **Trace ID** | Identificativo univoco request end-to-end (W3C `traceparent` standard) | 9 | [W3C TraceContext](https://www.w3.org/TR/trace-context/) |
| **TTL** | Time To Live: scadenza cache/record DNS/token | 6, 10 | — |
| **TypeVar** | `typing.TypeVar`: parametro tipo per generics (`TypeVar('T')`) | 1 | [PEP 484](https://peps.python.org/pep-0484/#type-variables) |

## U

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **Unit of Work** | Pattern: traccia cambiamenti oggetti, flush atomico in transazione | 5 | [Martin Fowler](https://martinfowler.com/eaaCatalog/unitOfWork.html) |
| **Uvicorn** | Server ASGI veloce (uvloop + httptools) | 4 | [Uvicorn](https://www.uvicorn.org/) |

## W

| Termine | Definizione | Capitolo | Riferimento |
|---------|-------------|----------|-------------|
| **W3C TraceContext** | Standard header `traceparent` / `tracestate` per propagazione trace | 9 | [W3C TraceContext](https://www.w3.org/TR/trace-context/) |
| **Write-Through** | Cache aggiornata sincronamente su scrittura DB | 10 | [Write-Through](https://learn.microsoft.com/en-us/azure/architecture/patterns/write-through) |

---

## Indice per Capitolo

| Capitolo | Termini Chiave |
|----------|----------------|
| 1. Python Fundamentals | Annotated, Dataclass, Protocol, TypeVar, Pydantic, Structured Logging |
| 2. HTTP & Networking | ALPN, CORS, HATEOAS, HTTP/2, HTTP/3, QUIC, TLS, Safe Method, W3C TraceContext |
| 3. REST Design | HATEOAS, Problem Details (RFC 7807), Richardson Maturity Model |
| 4. FastAPI | ASGI, Dependency Injection, Middleware, OpenAPI, Uvicorn, Starlette |
| 5. Database & ORM | Dialect, Eager/Lazy Loading, Identity Map, Migration, MVCC, N+1, Pool, Savepoint, Unit of Work |
| 6. Auth | ABAC, Bcrypt, CSRF, HMAC, JWT, OIDC, PKCE, RBAC, Refresh Token, Rate Limiting |
| 7. Testing | Fixture, Mock, Parametrizazione, TDD, Coverage, Factory, Testcontainers |
| 8. Deployment | Circuit Breaker, Graceful Shutdown, Gunicorn, Health Check, Rolling Update, Reverse Proxy |
| 9. Observability | Exemplar, OpenTelemetry, RED Metrics, Span, Structured Logging, Trace ID, W3C TraceContext |
| 10. Advanced | Cache-Aside, CQRS, Event Sourcing, Idempotency Key, Message Queue, Write-Through |

---

## Risorse Ufficiali Consigliate

| Argomento | Link |
|-----------|------|
| Python Type Hints | https://docs.python.org/3/library/typing.html |
| FastAPI | https://fastapi.tiangolo.com/ |
| SQLAlchemy 2.0 | https://docs.sqlalchemy.org/en/20/ |
| Pydantic v2 | https://docs.pydantic.dev/ |
| pytest | https://docs.pytest.org/ |
| OpenTelemetry Python | https://opentelemetry.io/docs/instrumentation/python/ |
| Prometheus | https://prometheus.io/docs/introduction/overview/ |
| Celery | https://docs.celeryq.dev/ |
| Redis | https://redis.io/docs/ |
| PostgreSQL | https://www.postgresql.org/docs/ |
| Nginx | https://nginx.org/en/docs/ |
| Docker | https://docs.docker.com/ |
| Kubernetes | https://kubernetes.io/docs/home/ |

---

*Ultimo aggiornamento: 2025-07-16*  
*Versione corso: 1.0*