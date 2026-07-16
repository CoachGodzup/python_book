# Capitolo 3 — Progettazione API REST

## Cos'è REST

REST (Representational State Transfer) è uno stile architetturale definito da Roy Fielding (2000). Non è uno standard né un protocollo: è un insieme di vincoli che, se rispettati, producono sistemi scalabili, evolvibili e interoperabili.

I sei vincoli formali:
1. **Client-Server** — Separazione delle responsabilità
2. **Stateless** — Ogni request contiene tutto il contesto necessario
3. **Cacheable** — Le risposte dichiarano esplicitamente cacheability
4. **Uniform Interface** — Interfaccia uniforme (risorse, metodi, rappresentazioni, HATEOAS)
5. **Layered System** — Intermediari (proxy, gateway) trasparenti
6. **Code on Demand** (opzionale) — Estensibilità client via codice scaricato

In pratica, *RESTful* significa: **risorse identificate da URI, manipulate tramite metodi HTTP standard, con rappresentazioni auto-descrittive.**

## RPC vs REST: Differenza Concettuale

### RPC (Remote Procedure Call) — *Action-Oriented*
```
GET    /getUser?id=1
POST   /createUser
POST   /deleteUser?id=1
GET    /getUserPosts?userId=1
```
- Verbi nell'URL
- Coupling forte: il client deve conoscere i nomi delle "funzioni"
- Difficile da evolvere senza breaking changes

### REST — *Resource-Oriented*
```
GET    /users/1
POST   /users
DELETE /users/1
GET    /users/1/posts
```
- Sostantivi nell'URL (risorse)
- Verbi nei metodi HTTP
- Contratto stabile: l'URL identifica la risorsa, non l'operazione

## Identificazione delle Risorse

### Convenzioni di Naming

| Regola | Esempio | Rationale |
|--------|---------|-----------|
| **Plurale** | `/users`, `/tasks` | Collezione = risorsa contenitore |
| **Kebab-case** | `/user-profiles`, `/api-keys` | Leggibilità URL; RFC 3986 non prescrive, ma kebab-case è standard de facto |
| **Nomi concreti** | `/tasks` non `/task-items` | Evita suffissi generici |
| **Nidificazione ≤ 2 livelli** | `/projects/42/tasks` ✓ | `/projects/42/tasks/7/comments/3` ✗ |
| **Identificatori opachi** | `/users/550e8400-e29b` | UUID > integer (non enumerabili, merge-safe) |

### Gerarchia vs Relazioni

Preferire relazioni piatte con query parameters per filtrare:
```
# Invece di /projects/42/tasks/7/comments
GET /comments?task_id=7&project_id=42
```

## Operazioni CRUD Mappate su HTTP

| Operazione | Metodo | Path | Status Successo | Body Request | Body Response |
|------------|--------|------|-----------------|--------------|---------------|
| Create | `POST` | `/tasks` | `201 Created` | `TaskCreate` | `TaskRead` |
| Read (collection) | `GET` | `/tasks` | `200 OK` | — | `Page[TaskRead]` |
| Read (single) | `GET` | `/tasks/{id}` | `200 OK` | — | `TaskRead` |
| Replace | `PUT` | `/tasks/{id}` | `200 OK` / `204` | `TaskUpdate` | `TaskRead` / — |
| Partial Update | `PATCH` | `/tasks/{id}` | `200 OK` / `204` | `TaskPatch` | `TaskRead` / — |
| Delete | `DELETE` | `/tasks/{id}` | `204 No Content` | — | — |

### PUT vs PATCH
- **PUT**: Sostituzione completa. Il client invia la risorsa *intera*. Idempotente.
- **PATCH**: Modifica parziale. Formato: [JSON Patch](https://tools.ietf.org/html/rfc6902) (`[{"op": "replace", "path": "/title", "value": "New"}]`) o [JSON Merge Patch](https://tools.ietf.org/html/rfc7396) (`{"title": "New"}`). Non garantito idempotente.

## Paginazione, Filtraggio, Ordinamento

### Paginazione: Cursor vs Offset

| Strategia | Vantaggi | Svantaggi |
|-----------|----------|-----------|
| **Offset** (`page`, `per_page`) | Semplice, salti arbitrari | Lento su offset grandi; risultati inconsistenti se dati mutano |
| **Cursor** (`after`, `before`, `limit`) | Performante, stabile | Nessun salto arbitrario; ordinamento fisso |

**Raccomandazione**: Offset per UI con paginazione numerica; Cursor per feed infiniti, export, sync.

#### Response Schema (Offset)
```json
{
  "data": [...],
  "pagination": {
    "page": 2,
    "per_page": 20,
    "total": 342,
    "total_pages": 18
  }
}
```
Header addizionali: `X-Total-Count: 342`, `Link: <...page=3>; rel="next"`

#### Response Schema (Cursor)
```json
{
  "data": [...],
  "next_cursor": "eyJpZCI6MTAwfQ==",
  "has_more": true
}
```

### Filtraggio e Ordinamento
```python
@router.get("/tasks")
async def list_tasks(
    status: TaskStatus | None = Query(None, description="Filtra per stato"),
    priority: Priority | None = Query(None),
    assignee_id: UUID | None = Query(None),
    sort: TaskSortField = Query(TaskSortField.CREATED_AT),
    order: Literal["asc", "desc"] = Query("desc"),
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
):
    ...
```
Convenzioni:
- Parametri = campi filtraibili
- `sort` + `order` separati (non `sort=-created_at`)
- Validare `sort` contro whitelist (evita injection ORDER BY)

## HATEOAS: Hypermedia as the Engine of Application State

Il client scopre le azioni possibili dalla risposta, non da documentazione esterna.

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Task esempio",
  "status": "open",
  "_links": {
    "self":    { "href": "/api/v1/tasks/550e8400-e29b", "method": "GET" },
    "update":  { "href": "/api/v1/tasks/550e8400-e29b", "method": "PATCH" },
    "delete":  { "href": "/api/v1/tasks/550e8400-e29b", "method": "DELETE" },
    "assign":  { "href": "/api/v1/tasks/550e8400-e29b/assignee", "method": "POST" }
  }
}
```
Non obbligatorio, ma distingue API *matura* (Level 3 Richardson Maturity Model) da semplice RPC-over-HTTP.

## Gestione Errori Consistente

### Formato Unificato (RFC 7807 — Problem Details)
```json
{
  "type": "https://api.example.com/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "One or more fields failed validation",
  "instance": "/api/v1/tasks",
  "trace_id": "550e8400-e29b-41d4-a716-446655440000",
  "errors": [
    { "field": "title", "code": "too_short", "message": "Minimum 3 characters" },
    { "field": "due_date", "code": "past_date", "message": "Cannot be in the past" }
  ]
}
```

### Codici Errore Applicativi (Non HTTP Status)
| Codice | Significato |
|--------|-------------|
| `VALIDATION_ERROR` | Input non conforme a schema |
| `NOT_FOUND` | Risorsa inesistente |
| `CONFLICT` | Violazione unicità / concorrenza |
| `UNAUTHORIZED` | Autenticazione mancante/invalida |
| `FORBIDDEN` | Permessi insufficienti |
| `RATE_LIMITED` | Troppo richieste |
| `INTERNAL_ERROR` | Bug server (loggare con trace_id) |

## Versioning

### Strategia A: URL Prefix (Più Comune)
```
/api/v1/tasks
/api/v2/tasks
```
- Vantaggio: Esplicito, cacheable, debuggabile
- Svantaggio: Duplicazione router; client deve aggiornare URL

### Strategia B: Accept Header
```
Accept: application/vnd.example.v2+json
```
- Vantaggio: URL stabili; content negotiation nativo
- Svantaggio: Meno visibile; tooling limitato; caching complesso

### Strategia C: Custom Header
```
API-Version: 2
```
- Svantaggio: Non standard; proxy potrebbero stripparlo

**Default pragmatico**: URL prefix (`/api/v1/`). Migrare a header solo se versioning frequente e client controllati.

## Operazioni Bulk e Async

### Bulk Create
```
POST /api/v1/tasks/bulk
Content-Type: application/json

{ "items": [{ "title": "A" }, { "title": "B" }] }
```
Response: `201 Created` + array risultati (o `207 Multi-Status` per errori parziali).

### Long-Running Operations
```
POST /api/v1/reports
→ 202 Accepted
  Location: /api/v1/reports/123/status
  Retry-After: 30
```
Client polla `GET /reports/123/status` finché `status: "completed"`.

## Soft Delete e Audit

```python
class Task(Base):
    ...
    deleted_at: Mapped[datetime | None] = mapped_column(nullable=True)
    deleted_by: Mapped[UUID | None] = mapped_column(ForeignKey("users.id"), nullable=True)
```
- `GET /tasks` → esclude `deleted_at IS NOT NULL`
- `GET /tasks?include_deleted=true` → admin only
- `DELETE /tasks/{id}` → `UPDATE ... SET deleted_at = now()`
- `POST /tasks/{id}/restore` → `UPDATE ... SET deleted_at = NULL`

---

## Checklist Design Review

Prima di implementare un endpoint:

- [ ] Risorsa nominata al plurale, kebab-case
- [ ] Metodo HTTP semanticamente corretto
- [ ] Status code allineato a tabella
- [ ] Paginazione definita (offset o cursor)
- [ ] Filtri/ordinamento su campi whitelistati
- [ ] Errori in formato RFC 7807
- [ ] Versioning in URL prefix
- [ ] HATEOAS links per transizioni non ovvie
- [ ] Documentazione OpenAPI generata (non manuale)

---

## Glossario Capitolo 3

| Termine | Definizione | Riferimento |
|---------|-------------|-------------|
| **Resource** | Entità identificabile (informazione) target di interazione | [Fielding §5.2](https://roy.gbiv.com/untangled/2008/rest-apis-must-be-hypertext-driven) |
| **Representation** | Sequenza di byte + metadata che cattura stato risorsa | RFC 7231 §3 |
| **Uniform Interface** | Vincolo: identificazione risorse, manipolazione via rappresentazioni, messaggi auto-descrittivi, HATEOAS | Fielding §5.1.5 |
| **Idempotency Key** | Client-generated key per rendere POST idempotente | [Stripe Idempotency](https://stripe.com/docs/api/idempotent_requests) |
| **Problem Details** | Formato standard errori HTTP (RFC 7807) | [RFC 7807](https://tools.ietf.org/html/rfc7807) |

---

## Prossimo Capitolo

Nel **Capitolo 4** implementeremo queste convenzioni con FastAPI: routing, dependency injection, validazione automatica, middleware, error handling, background tasks e WebSocket.