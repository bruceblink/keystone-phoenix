# Keystone Phoenix

Elixir/Phoenix rewrite project for [Keystone](https://github.com/bruceblink/Keystone).

The project is managed with Mix and uses PostgreSQL from the first commit.

## Toolchain

- Elixir 1.20.x
- Erlang/OTP 29.x
- Phoenix 1.8.16
- Ecto SQL 3.14.x
- Postgrex 0.22.x
- Redix 1.10.x
- Bandit 1.14.x
- PostgreSQL 18.x
- Redis 8.6.x

The dependency versions are locked in [`mix.lock`](mix.lock). `mix.exs` keeps
the compatible minor version ranges so security and patch releases can be
updated with the normal Mix workflow.

## Local development

```bash
cp .env.example .env
docker compose up -d postgres redis
mix setup
mix phx.server
```

The API listens on <http://localhost:4000>.

Useful Mix commands:

```bash
mix format
mix test
mix ecto.create
mix ecto.migrate
mix ecto.rollback
MIX_ENV=prod mix release
```

The first implementation keeps the service API-first. The existing Keystone
frontend can call Phoenix JSON endpoints while Ecto owns PostgreSQL access.
LiveView pages will be added later for real-time operations and administration
scenarios where server-side interactive state is useful.

Implemented API slices currently include health checks, dictionary type/data
CRUD, Redis-backed dictionary lookups, and system configuration CRUD with
validated option values and cache refresh support.

## PostgreSQL and Redis configuration

Development and test configuration reads `POSTGRES_*` environment variables.
Dictionary lookups by type use Redis with a five-minute TTL; writes invalidate
the corresponding key. Development reads `REDIS_URL`, while production
releases require `DATABASE_URL`, `REDIS_URL`, and `SECRET_KEY_BASE` from the
runtime environment. No database password is committed to the repository.
