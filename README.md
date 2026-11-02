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
- bcrypt_elixir 3.3.x
- JOSE 1.11.x
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
validated option values and cache refresh support. User list/detail queries and
default local accounts are also available as the foundation for authentication.
Local login, RS256 access/refresh tokens, refresh rotation, and protected user
queries are now available through `/login`, `/refresh-token`, and
`/system/users`. The `/login/rsa-public-key` endpoint returns a Base64 encoded
X.509 public key; clients encrypt the login password with RSA/PKCS#1 before
sending `/login`, matching the original Keystone contract.

## PostgreSQL and Redis configuration

Development and test configuration reads `POSTGRES_*` environment variables.
Dictionary lookups by type use Redis with a five-minute TTL; writes invalidate
the corresponding key. Development reads `REDIS_URL`, while production
releases require `DATABASE_URL`, `REDIS_URL`, and `SECRET_KEY_BASE` from the
runtime environment. Production authentication also requires the PEM encoded
`JWT_PRIVATE_KEY` value; `JWT_PUBLIC_KEY` is optional and is derived from the
private key when omitted. The private key signs JWTs and decrypts RSA login
passwords. Development generates an ephemeral RSA key pair when those values
are omitted. No database password is committed to the repository.

The seeded development users use password `123456`; replace those credentials
before exposing a deployment outside local development.
