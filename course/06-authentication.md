# Capitolo 6 — Autenticazione e Autorizzazione

## Distinzione Fondamentale

| Concetto | Domanda | Meccanismo |
|----------|---------|------------|
| **Autenticazione** (AuthN) | "Chi sei?" | Verifica credenziali → identità |
| **Autorizzazione** (AuthZ) | "Cosa puoi fare?" | Policy su identità autenticata |

Prima AuthN, poi AuthZ. Mai invertire.

---

## Modello Utente e Password Hashing

```python
# app/models/user.py
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Boolean, DateTime, func
from uuid import UUID, uuid4
from datetime import datetime

class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    full_name: Mapped[str | None] = mapped_column(String(100))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_superuser: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

### Hashing con `passlib` + `bcrypt`

```python
# app/core/security.py
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
```

- `bcrypt`: work factor configurabile (default 12), resistente a GPU/ASIC
- `argon2id`: alternativo moderno, vincitore PHC 2015 (richiede `argon2-cffi`)
- **Mai** rolling your own crypto. Mai `md5`, `sha256`, `sha512` per password.

---

## JWT: JSON Web Token (RFC 7519)

Token **stateless**, auto-contenuto, firmato (non criptato).

### Struttura
```
xxxxx.yyyyy.zzzzz
  │      │      └─ Signature (HS256/RS256)
  │      └─────── Payload (claims)
  └───────────── Header (alg, typ)
```

### Claims Standard (RFC 7519 §4)
| Claim | Significato |
|-------|-------------|
| `iss` | Issuer |
| `sub` | Subject (user ID) |
| `aud` | Audience |
| `exp` | Expiration (UNIX timestamp) |
| `nbf` | Not Before |
| `iat` | Issued At |
| `jti` | JWT ID (univoco, per revoca) |

### Implementazione

```python
# app/core/security.py
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from app.core.config import settings

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 15
REFRESH_TOKEN_EXPIRE_DAYS = 7

def create_token(subject: str, expires_delta: timedelta, token_type: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "type": token_type,
        "iat": now,
        "exp": now + expires_delta,
        "jti": uuid4().hex,  # per revoca/blacklist
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)

def create_access_token(user_id: UUID) -> str:
    return create_token(str(user_id), timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES), "access")

def create_refresh_token(user_id: UUID) -> str:
    return create_token(str(user_id), timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS), "refresh")

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise InvalidTokenError()
```

### Access Token + Refresh Token Pattern

```
┌─────────────┐     POST /auth/login      ┌─────────────┐
│   Client    │ ───────────────────────> │   Server    │
└─────────────┘  {email, password}       └─────────────┘
      ▲                                      │
      │         {access_token,               │
      │          refresh_token}              │
      │ <────────────────────────────────────┘
      │
      │ GET /api/tasks
      │ Authorization: Bearer <access_token>
      ├────────────────────────────────────>│
      │                                     │
      │        200 OK + data                │
      │ <───────────────────────────────────┤
      │
      │ (access_token scaduto)
      │ POST /auth/refresh
      │ {refresh_token}
      ├────────────────────────────────────>│
      │                                     │
      │   {new_access_token,                │
      │    new_refresh_token} (rotate)      │
      │ <───────────────────────────────────┤
```

**Refresh token rotation**: ogni uso invalida il vecchio e ne emette uno nuovo. Rileva replay attack.

---

## Dependency: Current User

```python
# app/dependencies/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from jose import JWTError, jwt
from app.core.security import decode_token
from app.core.database import get_db
from app.models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            raise credentials_exception
        user_id = UUID(payload["sub"])
    except (JWTError, ValueError, KeyError):
        raise credentials_exception

    user = await db.get(User, user_id)
    if not user or not user.is_active:
        raise credentials_exception
    return user

async def get_current_active_user(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    return current_user
```

Uso:
```python
@router.get("/me", response_model=UserResponse)
async def read_me(current_user: User = Depends(get_current_active_user)):
    return current_user
```

---

## RBAC: Role-Based Access Control

```python
# app/models/role.py
from enum import StrEnum

class Role(StrEnum):
    USER = "user"
    ADMIN = "admin"
    MANAGER = "manager"

# In User model
role: Mapped[Role] = mapped_column(default=Role.USER)
```

```python
# app/dependencies/rbac.py
from functools import wraps
from fastapi import Depends, HTTPException, status

def require_roles(*allowed: Role):
    async def dependency(current_user: User = Depends(get_current_active_user)):
        if current_user.role not in allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )
        return current_user
    return dependency

# Uso
@router.delete("/admin/users/{user_id}", status_code=204)
async def delete_user(
    user_id: UUID,
    _: User = Depends(require_roles(Role.ADMIN)),
    db: AsyncSession = Depends(get_db),
):
    ...
```

Per permessi fini: **Policy-based** (Casbin, Oso) o **Attribute-Based** (ABAC).

---

## Rate Limiting

Protegge auth endpoints da brute force.

```python
# app/main.py
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@router.post("/auth/login")
@limiter.limit("5/minute")
async def login(request: Request, credentials: UserLogin, db: AsyncSession = Depends(get_db)):
    ...
```

- `key_func`: IP, user ID, API key
- Storage: in-memory (dev), Redis (prod) via `slowapi.RedisBackend`

---

## OAuth2 / OIDC: Social Login

Flusso **Authorization Code + PKCE** (RFC 7636) — raccomandato per SPA/mobile.

```python
# app/core/oauth.py
from authlib.integrations.starlette_client import OAuth
from app.core.config import settings

oauth = OAuth()
oauth.register(
    name="google",
    client_id=settings.GOOGLE_CLIENT_ID,
    client_secret=settings.GOOGLE_CLIENT_SECRET,
    server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
    client_kwargs={"scope": "openid email profile"},
)

# Routes
@router.get("/auth/login/google")
async def login_google(request: Request):
    redirect_uri = request.url_for("auth_google_callback")
    return await oauth.google.authorize_redirect(request, redirect_uri)

@router.get("/auth/callback/google")
async def auth_google_callback(request: Request, db: AsyncSession = Depends(get_db)):
    token = await oauth.google.authorize_access_token(request)
    user_info = token.get("userinfo")  # OIDC: email, sub, name, picture
    if not user_info or not user_info.get("email_verified"):
        raise HTTPException(400, "Email not verified")

    user = await get_or_create_user(db, user_info)
    access_token = create_access_token(user.id)
    refresh_token = create_refresh_token(user.id)
    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer"}
```

Provider supportati: Google, GitHub, Microsoft, GitLab, Apple, generico OIDC.

---

## Sicurezza: Checklist Operativa

- [ ] **HTTPS obbligatorio** in produzione (TLS 1.2+)
- [ ] `SECRET_KEY` ≥ 32 byte, random, solo in `.env` / secret manager
- [ ] Access token: 15–30 min; Refresh token: 7–30 giorni con rotation
- [ ] `Secure`, `HttpOnly`, `SameSite=lax` (o `strict`) per cookie se usati
- [ ] `Authorization: Bearer` per token; mai in URL query string
- [ ] Password: `bcrypt` (work factor ≥ 12) o `argon2id`
- [ ] Rate limit su `/login`, `/register`, `/refresh`, `/forgot-password`
- [ ] Account lockout dopo N tentativi falliti (es. 5 in 15 min)
- [ ] Email verification obbligatoria prima di attivare account
- [ ] Password reset: token monouso, scadenza 1h, invalidato su uso
- [ ] Logging: `trace_id`, `user_id`, `ip`, `endpoint` — **mai** password/token
- [ ] CORS: `allow_origins` esplicito, no `["*"]` in prod
- [ ] Security headers: `Content-Security-Policy`, `X-Frame-Options`, `Referrer-Policy`

---

## Glossario Capitolo 6

| Termine | Definizione |
|---------|-------------|
| **JWT** | JSON Web Token — token compatto, auto-contenuto, firmato (JWS) o criptato (JWE) |
| **JWS** | JSON Web Signature — JWT firmato (integrità + autenticità, non riservatezza) |
| **HS256** | HMAC-SHA256 — firma simmetrica (stessa chiave per firmare/verificare) |
| **RS256** | RSA-SHA256 — firma asimmetrica (chiave privata firma, pubblica verifica) |
| **PKCE** | Proof Key for Code Exchange — estensione OAuth2 per prevenire auth code interception |
| **OIDC** | OpenID Connect — strato identità su OAuth2 (standardizza `userinfo`, `id_token`) |
| **RBAC** | Role-Based Access Control — permessi assegnati a ruoli, ruoli ad utenti |
| **ABAC** | Attribute-Based Access Control — policy su attributi (utente, risorsa, ambiente) |
| **Refresh Token Rotation** | Ogni uso del refresh token ne emette uno nuovo e invalida il precedente |

---

## Prossimo Capitolo

Nel **Capitolo 7** testeremo l'API: `pytest`, `TestClient`, fixture database isolato, mock servizi esterni, parametrizzazione, coverage, e TDD per feature critiche.