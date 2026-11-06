# Java Keystone parity audit

The first migration phase targets the Java API contract and the existing
`bruceblink/keystone-frontend`. The following compatibility slices are now
implemented in Phoenix:

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
| LiveView management pages | Functional coverage is complete; visual interaction parity remains an optimization task |

The Java project has no automatic PostgreSQL data migration because its
production data may still be in MySQL. Existing deployments need an explicit
ETL or dump/transform/import run for `sys_*` tables and a verification of
sequence values before switching traffic. The Phoenix migrations and seeds
cover a new PostgreSQL database only.

Remaining second-phase work is operational rather than missing core API
behavior: provide a repeatable MySQL-to-PostgreSQL migration command with
checksums, broaden browser-level LiveView compatibility tests, unify repeated
domain pagination helpers, and publish a release after a production database
restore rehearsal.
