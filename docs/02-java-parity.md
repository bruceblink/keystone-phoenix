# Java Keystone parity audit

The first migration phase targets a fully usable Keystone replacement. The
Java API and existing frontend are compatibility references, not a requirement
for visual or implementation-level 1:1 reproduction. The following functional
slices are implemented in Phoenix:

| Area | Phoenix status |
| --- | --- |
| Authentication, RSA login, RS256 access/refresh tokens, single-account sessions | Complete; sessions are PostgreSQL-backed |
| Users, departments, posts, roles, menus, notices, configs, dictionaries | Complete CRUD and validation boundaries |
| Role menu permissions and data scopes | Complete for API authorization and target mutations |
| Login/operation logs and automatic write auditing | Complete with sensitive-value redaction |
| Generic files and avatar resources | Complete with traversal, type, size, and signature checks |
| Excel user import/template and user/post/role/log exports | Complete with Elixlsx/Xlsxir |
| Jobs, allow-listed invocation, cron scheduling, execution logs | Complete |
| ETS cache replacement, rate limits, repeat protection, session cleanup | Complete for the current single-node deployment model |
| Java route aliases (`PUT /system/post`, `POST /logout`, notice replica demo) | Complete; the replica route uses the PostgreSQL query boundary |
| LiveView management pages | Functional coverage is complete; visual differences are optional follow-up work |

The current `main` branch is the usable baseline for subsequent iterations.
The Java project has no automatic PostgreSQL data migration because its
production data may still be in MySQL. Existing deployments can add an
explicit ETL or dump/transform/import run for `sys_*` tables later; this does
not block development or use of a new PostgreSQL deployment. The Phoenix
migrations and seeds cover a new PostgreSQL database.

Future work is iterative optimization: optional MySQL ETL tooling, broader
browser-level tests, shared domain pagination helpers, and observability
improvements. None of these are prerequisites for the current usable version.
