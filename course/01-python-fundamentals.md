# Capitolo 1 — Python Fundamentals

## Il linguaggio per il backend moderno

Python è lo standard de facto per API backend, data engineering, machine learning e automazione. La sua sintassi esplicita, il sistema di tipi graduale e l'ecosistema maturo lo rendono la scelta naturale per servizi che devono essere corretti, manutenibili e scalabili.

Per chi proviene da linguaggi a tipizzazione statica (TypeScript, Java, C#, Go) o da JavaScript, le differenze principali sono concettuali, non sintattiche.

## Type Hints: Tipizzazione Graduale

Python 3.5+ introduce type hints opzionali (PEP 484). Non sono enforceati a runtime — servono a IDE, linter (`mypy`, `pyright`) e documentazione.

```python
def sum_even(numbers: list[int]) -> int:
    return sum(n for n in numbers if n % 2 == 0)
```

Differenze chiave rispetto a TypeScript:
- `list[int]`, `dict[str, int]`, `tuple[int, str]` — sintassi nativa, non `Array<number>` o `Record<string, number>`
- `int | None` o `Optional[int]` per nullable (Python 3.10+)
- `Callable[[int, str], bool]` per firme di funzioni
- `TypeVar`, `Generic` per polimorfismo parametrico

Il tipo `Any` disattiva il controllo; usarlo con parsimonia.

## Strutture Dati Fondamentali

| Python | Descrizione | Equivalente concettuale |
|--------|-------------|------------------------|
| `list[T]` | Sequenza mutabile, indicizzata | Array dinamico |
| `tuple[T, ...]` | Sequenza immutabile, lunghezza fissa | Record/tupla |
| `dict[K, V]` | Mappa hash ordinata (3.7+) | `Map<K, V>` / Object |
| `set[T]` | Collezione unica, non ordinata | `Set<T>` |
| `frozenset[T]` | Set immutabile, hashabile | — |

Costruzione dichiarativa (comprehension):
```python
# List comprehension
evens = [x for x in range(100) if x % 2 == 0]

# Dict comprehension
index = {user.id: user for user in users}

# Set comprehension
unique_domains = {email.split("@")[1] for email in emails}
```

## Firme di Funzione Avanzate

Python separa argomenti posizionali, keyword-only e variadici:

```python
def create_user(
    name: str,                    # positional or keyword
    *,
    email: str,                   # keyword-only (dopo *)
    roles: list[str] | None = None,  # default mutabile evitato
    **extra: str | int            # **kwargs tipizzato
) -> User: ...
```

- `*args: tuple[T, ...]` — argomenti posizionali variadici
- `**kwargs: dict[str, T]` — argomenti keyword variadici
- `/` (solo posizionali) e `*` (solo keyword) controllano la calling convention

## Programmazione Asincrona

Il modello `async`/`await` di Python è cooperativo, basato su `asyncio`. Differenze rispetto a JavaScript:

- Event loop esplicito: `asyncio.run(main())` o loop gestito dal framework (FastAPI, Starlette)
- Nessuna microtask queue implicita; `await` cede controllo solo su I/O o `await asyncio.sleep(0)`
- `asyncio.gather()`, `asyncio.TaskGroup` (3.11+) per concorrenza strutturata

```python
async def fetch_all(urls: list[str]) -> list[Response]:
    async with aiohttp.ClientSession() as session:
        tasks = [fetch(session, url) for url in urls]
        return await asyncio.gather(*tasks)
```

Bloccare l'event loop con CPU-bound work richiede `asyncio.to_thread()` o `ProcessPoolExecutor`.

## Pydantic: Validazione a Runtime

Pydantic trasforma type hints in validazione concreta. È il cuore di FastAPI, delle settings (`pydantic-settings`) e della serializzazione sicura.

```python
from pydantic import BaseModel, EmailStr, Field, field_validator
from typing import Annotated

class UserCreate(BaseModel):
    name: Annotated[str, Field(min_length=2, max_length=50)]
    email: EmailStr
    age: Annotated[int, Field(ge=0, le=150)]

    @field_validator("name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Name cannot be blank")
        return v.strip()
```

Caratteristiche distintive:
- Coercizione sicura: `"42"` → `42` per `int`, `"true"` → `True` per `bool`
- Modelli annidati, union discriminati (`Union[User, Admin]` con `Field(discriminator='role')`)
- `model_config = ConfigDict(extra='forbid', frozen=True, populate_by_name=True)`
- Serializzazione: `model.model_dump(mode='json')`, `model.model_dump_json()`

## Context Manager: Gestione Deterministica delle Risorse

Il protocollo `with` garantisce cleanup anche in presenza di eccezioni — equivalente a `try`/`finally` o `using` (C#).

```python
# Built-in
with open("config.yaml") as f:
    config = yaml.safe_load(f)

with Session(engine) as session:
    session.add(user)
    session.commit()  # rollback automatico su eccezione
```

Implementazione custom:

```python
from contextlib import contextmanager
from time import perf_counter

@contextmanager
def measure(label: str):
    start = perf_counter()
    try:
        yield
    finally:
        elapsed = perf_counter() - start
        logger.info(f"{label} took {elapsed:.3f}s")

# Uso
with measure("db_query"):
    results = db.query(...)
```

Per classi: `__enter__` restituisce la risorsa, `__exit__(exc_type, exc_val, exc_tb)` gestisce cleanup; restituire `True` sopprime l'eccezione.

## Pattern Matching (Python 3.10+)

`match`/`case` è structural pattern matching, non un semplice `switch`. Confronta la forma dei dati, non solo valori.

```python
from dataclasses import dataclass
from typing import Literal

@dataclass
class ClickEvent:
    type: Literal["click"]
    x: int
    y: int

@dataclass
class KeyEvent:
    type: Literal["keypress"]
    key: str

Event = ClickEvent | KeyEvent

def handle(event: Event) -> str:
    match event:
        case ClickEvent(x=x, y=y) if x > 0 and y > 0:
            return f"Click at ({x}, {y})"
        case KeyEvent(key=k):
            return f"Key: {k}"
        case _:
            return "Unknown"
```

Elementi avanzati:
- Guardie: `case ClickEvent(x=x) if x > 100:`
- Cattura resto: `case [first, *rest, last]:`
- Mapping pattern: `case {"type": "click", **payload}:`
- Class pattern con attributi: `case ClickEvent(x=10, y=y):`

## Dataclass: Contenitori di Dati Puri

Per oggetti che sono principalmente stato, senza logica di validazione complessa:

```python
from dataclasses import dataclass, field
from datetime import datetime
from uuid import uuid4

@dataclass(slots=True, frozen=True, kw_only=True)
class Product:
    name: str
    price_cents: int
    tags: list[str] = field(default_factory=list)
    id: str = field(default_factory=lambda: uuid4().hex)
    created_at: datetime = field(default_factory=datetime.utcnow)

    @property
    def price_eur(self) -> float:
        return self.price_cents / 100
```

Opzioni chiave:
- `slots=True` — memoria ridotta, attributi fissi (3.10+)
- `frozen=True` — immutabilità
- `kw_only=True` — solo keyword arguments (3.10+)
- `field(default_factory=...)` — default mutabili sicuri
- `field(compare=False, repr=False, hash=False)` — controllo protocolli

## Enum: Costanti Tipizzate

```python
from enum import StrEnum, auto, Enum

class Priority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

class Status(Enum):
    PENDING = auto()
    PROCESSING = auto()
    COMPLETED = auto()
    FAILED = auto()
```

`StrEnum` (3.11+) rende i membri confrontabili con stringhe: `priority == "high"`. `auto()` assegna valori incrementali univoci.

## Checklist di Padronanza

Prima di proseguire, verifica confidenza con:

- [ ] Type hints per funzioni, classi, generics (`TypeVar`, `Protocol`)
- [ ] Comprehension (list, dict, set, generator)
- [ ] Firme avanzate: `*args`, `**kwargs`, keyword-only, positional-only
- [ ] `async`/`await`, `asyncio.gather`, `TaskGroup`, `to_thread`
- [ ] Modelli Pydantic: validatori, coercizione, configurazione, serializzazione
- [ ] Context manager built-in e custom (`contextmanager`, classe)
- [ ] Pattern matching: class pattern, guardie, mapping, sequence
- [ ] `@dataclass`: `slots`, `frozen`, `kw_only`, `field()`
- [ ] `StrEnum`, `IntEnum`, `auto()` per costanti tipizzate

---

## Prossimo Capitolo

Nel **Capitolo 2** analizzeremo come i dati viaggiano sulla rete: protocollo HTTP, semantica dei metodi, codici di stato, header, e le basi TCP/TLS necessarie per costruire API robuste.