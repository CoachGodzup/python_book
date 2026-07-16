# Capitolo 5 — Database e ORM: SQLAlchemy 2.0 (Async)

## Perché SQLAlchemy

SQLAlchemy è l'ORM Python *de facto*: maturo, flessibile, type-safe (2.0+), supporta sync e async nativamente. Non nasconde SQL — lo espone come costrutti Python componibili.

---

## Engine e Session: Async-First

```python
# app/core/database.py
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,           # postgresql+asyncpg://user:pass@host/db
    echo=settings.DEBUG,             # Log SQL in dev
    pool_pre_ping=True,              # Verifica connessione prima uso
    pool_size=10,                    # Connessioni persistenti
    max_overflow=20,                 # Extra sotto carico
)

async_session_maker = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

class Base(DeclarativeBase):
    pass
```

### Dependency FastAPI

```python
# app/dependencies/db.py
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import async_session_maker

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session
```

Uso:
```python
@router.get("/tasks")
async def list_tasks(db: AsyncSession = Depends(get_db)) -> list[TaskResponse]:
    result = await db.execute(select(Task).order_by(Task.created_at.desc()))
    return result.scalars().all()
```

---

## Modelli: Mapped, mapped_column, Relationship

```python
# app/models/task.py
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import String, Boolean, DateTime, ForeignKey, Text, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from app.core.database import Base
from app.schemas.enums import Priority, TaskStatus
import uuid
from datetime import datetime

class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[TaskStatus] = mapped_column(SQLEnum(TaskStatus), default=TaskStatus.OPEN, nullable=False)
    priority: Mapped[Priority] = mapped_column(SQLEnum(Priority), default=Priority.MEDIUM, nullable=False)
    due_date: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # FK
    project_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="SET NULL"), nullable=True, index=True)
    assignee_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

    # Relationships
    project: Mapped["Project | None"] = relationship(back_populates="tasks")
    assignee: Mapped["User | None"] = relationship(back_populates="assigned_tasks")
    tags: Mapped[list["Tag"]] = relationship(secondary="task_tags", back_populates="tasks")
```

Punti chiave:
- `Mapped[T]` + `mapped_column()` → type hints + DDL
- `UUID(as_uuid=True)` → native UUID Postgres
- `SQLEnum(EnumClass)` → enum nativo DB + validazione Python
- `ondelete="SET NULL" | "CASCADE"` → referential integrity
- `index=True` su FK → join performance
- `expire_on_commit=False` evita reload post-commit

---

## Relazioni: One-to-Many, Many-to-Many

### One-to-Many (Project → Tasks)

```python
class Project(Base):
    __tablename__ = "projects"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    tasks: Mapped[list[Task]] = relationship(back_populates="project", lazy="selectin")
```

### Many-to-Many (Task ↔ Tag)

```python
# Association table (no model needed se solo FK)
task_tags = Table(
    "task_tags", Base.metadata,
    Column("task_id", UUID(as_uuid=True), ForeignKey("tasks.id", ondelete="CASCADE"), primary_key=True),
    Column("tag_id", UUID(as_uuid=True), ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True),
)

class Tag(Base):
    __tablename__ = "tags"
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    tasks: Mapped[list[Task]] = relationship(secondary=task_tags, back_populates="tags", lazy="selectin")
```

---

## Il Problema N+1 e `selectinload`

```python
# ❌ N+1: 1 query tasks + N query project
result = await db.execute(select(Task).limit(100))
tasks = result.scalars().all()
for t in tasks:
    print(t.project.name)  # Ogni accesso = query!

# ✅ Eager loading: 2 query totali (tasks + projects)
from sqlalchemy.orm import selectinload
result = await db.execute(
    select(Task).options(selectinload(Task.project)).limit(100)
)
tasks = result.scalars().all()
```

Regola: **sempre** `selectinload` per collection, `joinedload` per scalar (se 1:1 o M:1 e serve sempre).

```python
# Joined load per scalar (single LEFT JOIN)
select(User).options(joinedload(User.profile))

# Selectin per collection (IN query separata)
select(User).options(selectinload(User.tasks))
```

---

## Query Avanzate: Core Expression Language

```python
from sqlalchemy import select, func, and_, or_, exists, delete, update
from sqlalchemy.orm import contains_eager

# Filtri complessi
stmt = select(Task).where(
    and_(
        Task.status == TaskStatus.OPEN,
        or_(Task.assignee_id == user_id, Task.project_id.in_(project_ids)),
        Task.due_date <= datetime.utcnow() if overdue else True,
    )
).order_by(Task.priority.desc(), Task.created_at).limit(20)

# Aggregazioni
stmt = select(
    Task.status,
    func.count(Task.id).label("count")
).group_by(Task.status)

# Subquery / CTE
subq = select(Task.project_id, func.count(Task.id).label("task_count")).group_by(Task.project_id).cte()
stmt = select(Project).join(subq, Project.id == subq.c.project_id).where(subq.c.task_count > 10)

# Delete bulk
await db.execute(delete(Task).where(Task.status == TaskStatus.ARCHIVED, Task.updated_at < cutoff))

# Update bulk
await db.execute(update(Task).where(Task.project_id == pid).values(project_id=None))
```

---

## Transazioni: Unit of Work

```python
# Transazione esplicita (auto-commit/rollback su exception)
async with db.begin():
    task = Task(title="New", project_id=pid)
    db.add(task)
    await db.flush()  # Assegna ID, non commit
    log = TaskLog(task_id=task.id, action="created")
    db.add(log)
# commit automatico qui, rollback se exception

# Savepoint (nested transaction)
async with db.begin():
    await do_something()
    try:
        async with db.begin_nested():  # SAVEPOINT
            await risky_operation()
    except Exception:
        pass  # Rollback al savepoint, transazione principale continua
```

---

## Migrazioni: Alembic

```bash
# Init (una volta)
alembic init alembic

# Config env.py per async
# target_metadata = Base.metadata
# run_migrations_online() usa AsyncEngine

# Genera migration automatica
alembic revision --autogenerate -m "add task table"

# Applica
alembic upgrade head

# Rollback
alembic downgrade -1
```

### Best Practices Migration
- **Rivedi sempre** il file generato (`--autogenerate` non è magico)
- Nomi espliciti: `alembic revision -m "add due_date to tasks"`
- `batch_alter_table` per SQLite (non supporta `ALTER COLUMN` nativo)
- Dati + schema separati: migration dati in file dedicato
- Test `upgrade` + `downgrade` in CI

---

## Da SQLite (Dev) a PostgreSQL (Prod)

| Caratteristica | SQLite | PostgreSQL |
|----------------|--------|------------|
| Concurrency | Serialized writes | MVCC, multi-writer |
| JSON | JSON1 extension | **JSONB** (indici GIN, query `@>`, `?`) |
| Full-text | No | `tsvector`, `tsquery`, GIN/GiST |
| Tipi nativi | Limitati | UUID, ARRAY, ENUM, RANGE, CITEXT, INET |
| Produzione | No | Sì |

### Connection String

```python
# Dev
DATABASE_URL = "sqlite+aiosqlite:///./dev.db"

# Prod
DATABASE_URL = "postgresql+asyncpg://user:pass@host:5432/dbname?ssl=require"
```

### Pool Sizing (PostgreSQL)
```python
# Calcolo: (core_count * 2) + effective_spindle_count
# Es. 4 core SSD → pool_size=10, max_overflow=20
engine = create_async_engine(
    url,
    pool_size=10,
    max_overflow=20,
    pool_timeout=30,
    pool_recycle=1800,      # Ricicla connessioni > 30 min
    pool_pre_ping=True,     # SELECT 1 prima prestito
)
```

---

## SQLModel: Alternative Leggera

[SQLModel](https://sqlmodel.tiangolo.com/) = Pydantic + SQLAlchemy, stesso autore di FastAPI. Un'unica classe per model ORM + schema API.

```python
from sqlmodel import SQLModel, Field, Relationship

class Task(SQLModel, table=True):
    id: uuid.UUID | None = Field(default_factory=uuid.uuid4, primary_key=True)
    title: str = Field(max_length=200)
    project_id: uuid.UUID | None = Field(default=None, foreign_key="projects.id")
    project: "Project | None" = Relationship(back_populates="tasks")
```

Usa SQLAlchemy sotto il cofano; migra a SQLAlchemy puro se serve controllo fine.

---

## Checklist Database

- [ ] `asyncpg` driver per PostgreSQL async
- [ ] `expire_on_commit=False` in session maker
- [ ] Indici su tutte le FK e campi filtrati frequentemente
- [ ] `selectinload` / `joinedload` su ogni endpoint che accede relazioni
- [ ] Transazioni esplicite per operazioni multi-step
- [ ] Alembic configurato, migration testate in CI
- [ ] Connection pool sizing per carico atteso
- [ ] `pool_pre_ping=True` per resilienza
- [ ] Backup strategy (pg_dump, point-in-time recovery)
- [ ] Read replica per query pesanti (CQRS, vedi Cap. 10)

---

## Glossario Capitolo 5

| Termine | Definizione |
|---------|-------------|
| **Unit of Work** | Pattern: traccia cambiamenti su oggetti, flush atomico in transazione |
| **Identity Map** | Cache in-session: stesso PK = stessa istanza Python |
| **Lazy Loading** | Caricamento relazione al primo accesso (N+1 risk) |
| **Eager Loading** | Caricamento proattivo via `JOIN` o `IN` query separata |
| **selectinload** | Eager loading con `WHERE id IN (...)` — ottimale per collection |
| **joinedload** | Eager loading con `LEFT JOIN` — ottimale per scalar |
| **MVCC** | Multi-Version Concurrency Control — letture non bloccanti (PostgreSQL) |
| **CTE** | Common Table Expression — `WITH ... SELECT` query componibili |

---

## Prossimo Capitolo

Nel **Capitolo 6** implementeremo autenticazione e autorizzazione: password hashing, JWT, refresh token, RBAC, rate limiting, e OAuth2 social login.