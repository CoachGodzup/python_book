# Capitolo 2 — Fondamenti di Rete e HTTP

## Perché la rete è responsabilità del backend

Un client HTTP (`fetch`, `axios`, `httpx`) nasconde la complessità del trasporto. Un server non può permettersi questa astrazione: deve gestire connessioni parziali, timeout, backpressure, e le semantiche del protocollo. Comprendere TCP e HTTP non è accademico — è prerequisito per scrivere API corrette, performanti e sicure.

## TCP: Il Livello di Trasporto

HTTP si appoggia su TCP (Transmission Control Protocol). TCP fornisce:
- **Connessione affidabile**: riordina pacchetti, ritrasmette persi
- **Flow control**: finestra scorrevole per evitare sovraccarico ricevente
- **Congestion control**: adatta il rate di invio alla capacità di rete

### Three-Way Handshake

Ogni connessione TCP richiede:
```
Client                    Server
  │                         │
  ├────── SYN ─────────────>│
  │<──── SYN-ACK ──────────┤
  │                         │
  ├────── ACK ─────────────>│
  │                         │
  ├────── DATA ────────────>│
```

Ogni handshake costa **1 RTT** (Round-Trip Time) prima del primo byte di dati. Su latenze tipiche (20-100ms), questo è significativo.

### Implicazioni Pratiche

| Concetto | Descrizione | Impatto |
|----------|-------------|---------|
| **Connection Pool** | Riutilizzo connessioni TCP per multiple request | Elimina handshake ripetuti |
| **Keep-Alive** | `Connection: keep-alive` (default HTTP/1.1) | Mantiene connessione aperta |
| **TCP_NODELAY** | Disabilita algoritmo Nagle (buffering piccoli pacchetti) | Riduce latenza per request piccole |
| **TLS Session Resumption** | Riusa parametri crittografici | Evita handshake TLS completo |

## HTTP: Struttura del Messaggio

### Request

```
POST /api/v1/tasks HTTP/1.1
Host: api.example.com
Content-Type: application/json
Authorization: Bearer eyJhbGc...
Content-Length: 42

{"title": "Nuovo task", "priority": "high"}
```

Componenti:
1. **Request Line**: `METHOD /path HTTP/version`
2. **Headers**: Metadati (key: value), terminati da `\r\n\r\n`
3. **Body**: Payload opzionale (assente in GET, HEAD, DELETE)

### Response

```
HTTP/1.1 201 Created
Content-Type: application/json
Location: /api/v1/tasks/123

{"id": 123, "title": "Nuovo task", "priority": "high"}
```

Componenti:
1. **Status Line**: `HTTP/version STATUS_CODE REASON`
2. **Headers**: Metadati risposta
3. **Body**: Rappresentazione della risorsa

## Metodi HTTP: Semantica e Garanzie

| Metodo | Safe | Idempotent | Cacheable | Body | Uso Primario |
|--------|------|------------|-----------|------|--------------|
| `GET` | ✅ | ✅ | ✅ | No | Recupero risorsa |
| `HEAD` | ✅ | ✅ | ✅ | No | Solo headers |
| `POST` | ❌ | ❌ | ❌* | Sì | Creazione / Azione |
| `PUT` | ❌ | ✅ | ❌ | Sì | Sostituzione completa |
| `PATCH` | ❌ | ❌** | ❌ | Sì | Modifica parziale |
| `DELETE` | ❌ | ✅ | ❌ | No | Rimozione |
| `OPTIONS` | ✅ | ✅ | ❌ | Opzionale | Discovery CORS |

* `POST` può essere cacheable se include `Content-Location` e `Expires` (raro).
** `PATCH` *può* essere idempotente se l'operazione lo è (es. `{"op": "replace", "path": "/a", "value": 1}`), ma lo standard non lo garantisce.

### Definizioni Formali (RFC 7231)

- **Safe**: Il metodo non richiede, né causa, modifiche allo stato del server. `GET`, `HEAD`, `OPTIONS`, `TRACE` sono safe.
- **Idempotent**: N richieste identiche hanno lo stesso effetto di una singola richiesta. `GET`, `HEAD`, `PUT`, `DELETE`, `OPTIONS`, `TRACE` sono idempotenti.
- **Cacheable**: La risposta può essere memorizzata da cache intermedie. `GET`, `HEAD`, `POST` (condizionale) sono cacheable.

## Status Code: Classificazione Rigorosa

### 1xx — Informational
| Codice | Significato |
|--------|-------------|
| `100 Continue` | Il server ha ricevuto gli headers; il client può inviare il body |
| `101 Switching Protocols` | Upgrade protocollo (es. WebSocket) |

### 2xx — Successo
| Codice | Significato | Uso Tipico |
|--------|-------------|------------|
| `200 OK` | Successo generico | GET, PUT, PATCH |
| `201 Created` | Risorsa creata | POST (con `Location` header) |
| `202 Accepted` | Richiesta accettata, processing asincrono | Task in background |
| `204 No Content` | Successo, nessun body | DELETE, PUT/PATCH senza risposta |

### 3xx — Redirezione
| Codice | Significato |
|--------|-------------|
| `301 Moved Permanently` | Risorsa spostata permanentemente (cacheable) |
| `302 Found` | Spostamento temporaneo |
| `304 Not Modified` | Cache valida (risposta a `If-None-Match`/`If-Modified-Since`) |
| `307 Temporary Redirect` | Come 302, ma preserva metodo e body |
| `308 Permanent Redirect` | Come 301, ma preserva metodo e body |

### 4xx — Errore Client
| Codice | Significato | Quando Usare |
|--------|-------------|--------------|
| `400 Bad Request` | Sintassi request malformata | JSON invalido, parametri mancanti |
| `401 Unauthorized` | Autenticazione mancante/invalida | Token assente, scaduto, firma invalida |
| `403 Forbidden` | Autenticato ma non autorizzato | Ruolo insufficiente, risorsa altrui |
| `404 Not Found` | Risorsa inesistente | ID non trovato |
| `409 Conflict` | Conflitto stato corrente | Duplicate unique constraint, versione obsoleta |
| `422 Unprocessable Entity` | Sintassi OK, semantica invalida | Validazione business logic fallita |
| `429 Too Many Requests` | Rate limit superato | Includere `Retry-After` header |

### 5xx — Errore Server
| Codice | Significato |
|--------|-------------|
| `500 Internal Server Error` | Errore non gestito (loggare, non esporre dettagli) |
| `502 Bad Gateway` | Proxy/gateway ha ricevuto risposta invalida da upstream |
| `503 Service Unavailable` | Sovraccarico temporaneo, manutenzione (usare `Retry-After`) |
| `504 Gateway Timeout` | Upstream non ha risposto in tempo |

> **Regola d'oro**: Mai esporre stack trace, query SQL, o dettagli interni in risposte 5xx. Loggare lato server con `trace_id`; restituire al client solo `{"detail": "Internal server error", "trace_id": "..."}`.

## Headers Essenziali

### Request Headers
| Header | Scopo | Esempio |
|--------|-------|---------|
| `Host` | Target authority (richiesto HTTP/1.1) | `api.example.com` |
| `Authorization` | Credenziali | `Bearer <jwt>`, `Basic <base64>` |
| `Content-Type` | Media type del body | `application/json` |
| `Accept` | Media type preferito risposta | `application/json` |
| `Accept-Encoding` | Compressioni supportate | `gzip, deflate, br` |
| `If-None-Match` | Validazione cache (ETag) | `"abc123"` |
| `If-Modified-Since` | Validazione cache (timestamp) | `Wed, 16 Jul 2025 10:00:00 GMT` |
| `X-Request-ID` / `X-Correlation-ID` | Trace ID cross-service | `uuid-v4` |

### Response Headers
| Header | Scopo |
|--------|-------|
| `Content-Type` | Media type del body |
| `Content-Length` | Dimensione body in byte (se noto) |
| `Transfer-Encoding: chunked` | Streaming senza Content-Length |
| `Location` | URL risorsa creata (201) o redirect (3xx) |
| `ETag` | Identificatore versione risorsa (per caching) |
| `Cache-Control` | Direttive caching (vedi sotto) |
| `Set-Cookie` | Imposta cookie client |
| `Access-Control-Allow-*` | CORS (vedi sezione dedicata) |
| `Retry-After` | Secondi o data per retry (429, 503) |

### Cache-Control: Direttive Chiave
```
Cache-Control: public, max-age=300, stale-while-revalidate=60
```
- `public` / `private` — Cacheabile da shared / solo client
- `max-age=N` — Secondi di freshness
- `s-maxage=N` — Override per shared cache (CDN)
- `no-store` — Non memorizzare mai
- `no-cache` — Rvalidare prima di usare (non "non cacheare")
- `must-revalidate` — Obbligo revalidazione se stale
- `stale-while-revalidate=N` — Servi stale mentre revalidi in background

## CORS: Cross-Origin Resource Sharing

### Il Problema
Same-Origin Policy (SOP) impedisce a `https://app.example.com` di chiamare `https://api.example.com`. Il browser blocca la risposta se il server non autorizza esplicitamente l'origin.

### La Soluzione (Server-Side)
Il server risponde con headers che dicono al browser: "questo origin può accedere".

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com", "https://admin.example.com"],
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    allow_credentials=True,           # Permette cookie/Authorization
    expose_headers=["X-Total-Count"], # Headers leggibili da JS
    max_age=86400,                    # Cache preflight (secondi)
)
```

### Preflight Request
Per request "non semplici" (es. `Authorization` header, `Content-Type: application/json`, metodi non GET/HEAD/POST), il browser invia prima:
```
OPTIONS /api/tasks HTTP/1.1
Origin: https://app.example.com
Access-Control-Request-Method: POST
Access-Control-Request-Headers: Authorization, Content-Type
```
Il server deve rispondere con i CORS headers appropriati. FastAPI/Starlette gestisce automaticamente `OPTIONS` se il middleware è configurato.

## Cookie vs Bearer Token

| Aspetto | Cookie (`Set-Cookie`) | Bearer Token (`Authorization: Bearer`) |
|---------|----------------------|----------------------------------------|
| Trasporto | Automatico (browser) | Esplicito (client JS) |
| Storage | Browser (HttpOnly, Secure, SameSite) | `localStorage` / `sessionStorage` / memoria |
| CSRF | Vulnerabile (serve `SameSite=Lax/Strict` + CSRF token) | Immune |
| XSS | Protetto se `HttpOnly` | Vulnerabile se `localStorage` compromesso |
| Scadenza | `Expires` / `Max-Age` + `SameSite` | Claim `exp` nel JWT |
| Revoca | Cancellazione server-side (session store) | Token blocklist / short expiry + refresh |
| Stato | Stateful (server memorizza sessione) | Stateless (JWT) o stateful (opaque token) |

### Cookie Sicuri (Produzione)
```python
response.set_cookie(
    key="session_id",
    value=session_id,
    httponly=True,        # Inaccessibile a JavaScript
    secure=True,          # Solo su HTTPS
    samesite="lax",       # Protezione CSRF (Strict per massime sicurezza)
    max_age=3600,         # 1 ora
    path="/",
)
```

## HTTPS e TLS

HTTPS = HTTP su TLS (Transport Layer Security). TLS fornisce:
1. **Confidenzialità**: Cifratura simmetrica (AES-GCM, ChaCha20-Poly1305)
2. **Integrità**: MAC / AEAD impedisce manipolazione
3. **Autenticazione**: Certificato X.509 + PKI verifica identità server

### Handshake TLS 1.3 (Semplificato)
```
Client                                          Server
  │                                                │
  ├──── ClientHello (cipher suites, key share) ──>│
  │<─── ServerHello, Certificate, Finished ──────┤
  │                                                │
  ├──── Finished, Application Data ─────────────>│
```

TLS 1.3 riduce a **1-RTT** (vs 2-RTT in 1.2) e rimuove cipher suite insicure.

### Certificati
- **Produzione**: Let's Encrypt (gratis, auto-rinnovo 90gg), ACME client (`certbot`, `acme.sh`, `traefik`, `caddy`)
- **Sviluppo**: Self-signed + trust locale, o `mkcert` per CA locale trusted

```bash
# mkcert (consigliato per dev)
mkcert -install
mkcert localhost 127.0.0.1 ::1
# Genera localhost+2.pem, localhost+2-key.pem
```

## Connection Pooling e HTTP/2

### HTTP/1.1
- 1 request per connessione alla volta (pipelining rotto nella pratica)
- Browser apre 6-8 connessioni parallele per host
- Headers testuali, verbosi, ripetuti

### HTTP/2 (RFC 7540)
- **Multiplexing**: Multiple stream su singola connessione TCP
- **Header Compression** (HPACK): Elimina ridondanza headers
- **Server Push**: Server invia risorse anticipate (deprecato in browser)
- **Prioritization**: Client segnala priorità stream

### HTTP/3 (QUIC)
- UDP-based, elimina head-of-line blocking TCP
- 0-RTT resumption
- Native connection migration (cambio IP senza reset)

### Configurazione Pool (httpx esempio)
```python
import httpx

limits = httpx.Limits(
    max_connections=100,        # Totale connessioni pool
    max_keepalive_connections=20, # Connessioni idle mantenute
    keepalive_expiry=30.0,      # Secondi prima chiusura idle
)

client = httpx.AsyncClient(limits=limits, http2=True)
```

---

## Glossario Capitolo 2

| Termine | Definizione | RFC |
|---------|-------------|-----|
| **RTT** | Round-Trip Time: tempo andata-ritorno pacchetto | — |
| **Safe Method** | Non modifica stato server | [7231§4.2.1](https://httpwg.org/specs/rfc7231.html#safe.methods) |
| **Idempotent Method** | N richieste = 1 richiesta | [7231§4.2.2](https://httpwg.org/specs/rfc7231.html#idempotent.methods) |
| **ETag** | Entity Tag: validatore cache forte/debole | [7232§2.3](https://httpwg.org/specs/rfc7232.html#entity.tags) |
| **Preflight** | Request `OPTIONS` automatica browser per CORS | [Fetch Spec](https://fetch.spec.whatwg.org/#cors-preflight-request) |
| **SameSite** | Attributo cookie che controlla invio cross-site | [RFC 6265bis](https://tools.ietf.org/html/draft-ietf-httpbis-rfc6265bis) |
| **ALPN** | Application-Layer Protocol Negotiation (HTTP/2 su TLS) | [RFC 7301](https://tools.ietf.org/html/rfc7301) |

---

## Prossimo Capitolo

Nel **Capitolo 3** definiremo come organizzare un'API usando i primitivi HTTP: progettazione REST, naming delle risorse, paginazione, filtraggio, versioning e gestione errori consistente.