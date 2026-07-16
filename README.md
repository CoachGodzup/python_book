# Python Backend Roadmap

> **⚠️ WIP** — This curriculum is a work in progress. Content and structure may change.

![Made with Markdown](https://img.shields.io/badge/made%20with-Markdown-1f425f.svg)

A 10-chapter course for frontend developers (TypeScript/JavaScript) transitioning to **modern Python backend API development**.

Topics progress from **Python fundamentals** through **production-grade concepts**: FastAPI, SQLAlchemy 2.0, Pydantic v2, authentication (JWT/OAuth2), testing, Docker, observability, message queues, and more.

## Structure

| Path | Description |
|---|---|
| `course/` | Reading material — one markdown file per chapter + glossary |
| `docs/` | Hands-on coding exercises — build a `taskmanager/` REST API incrementally |
| `ROADMAP.md` | Full curriculum outline with projects and resources |

## Topics

| # | Topic | Course | Docs |
|---|---|---|---|
| 1 | Python Fundamentals | [course](course/01-python-fundamentals.md) | [docs](docs/01-python-fundamentals.md) |
| 2 | HTTP & Networking | [course](course/02-http-networking.md) | [docs](docs/02-http-networking.md) |
| 3 | REST API Design | [course](course/03-rest-api-design.md) | [docs](docs/03-rest-api-design.md) |
| 4 | Web Framework (FastAPI) | [course](course/04-web-framework-fastapi.md) | [docs](docs/04-web-framework-fastapi.md) |
| 5 | Database & ORM | [course](course/05-database-orm.md) | [docs](docs/05-database-orm.md) |
| 6 | Authentication & Authorization | [course](course/06-authentication.md) | [docs](docs/06-authentication.md) |
| 7 | Testing | [course](course/07-testing.md) | [docs](docs/07-testing.md) |
| 8 | Deployment & DevOps | [course](course/08-deployment.md) | [docs](docs/08-deployment.md) |
| 9 | Monitoring & Observability | [course](course/09-monitoring.md) | [docs](docs/09-monitoring.md) |
| 10 | Advanced Concepts | [course](course/10-advanced-concepts.md) | [docs](docs/10-advanced-concepts.md) |

## Prerequisites

- Python 3.9+
- Basic programming knowledge (any language)
- Familiarity with TypeScript/JavaScript is helpful but not required

## Build

Generate the ebook (requires [pandoc](https://pandoc.org)):

```sh
make epub
```

## License

MIT

---

*Generated with Deepseek Flash V4 + Nemotron Ultra Free via [Opencode](https://opencode.ai)*
