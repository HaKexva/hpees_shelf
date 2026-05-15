# Demo shard: how “duplicate” data is stored

## There is no `CREATE DATABASE` migration

Rails migrations **do not create PostgreSQL databases**. You create the database (or Railway provisions it) and set `DATABASE_URL`. The app then runs migrations against each configured connection.

## How the demo copy works

- **Primary** (`config/database.yml` → `primary`) uses the default schema, usually **`public`**. Your real data lives in `public.users`, `public.books`, etc.
- **Demo** (`primary_shard_demo`) either:
  - uses the **same** `DATABASE_URL` with **`schema_search_path: demo`**, so the same migration files create **`demo.users`**, **`demo.books`**, … (a full parallel table set), or
  - uses a **separate** `DEMO_DATABASE_URL`, where those tables are created in **`public`** on that database only.

Migrations in `db/migrate/` are **shared**: when you run `bin/rails db:migrate`, Rails applies them to **every** app DB config (including `primary_shard_demo`). You do not need separate migration files per table for “demo”.

The only migration specific to the shared-DB setup is:

- `db/migrate/20260124054254_ensure_demo_schema.rb` — runs `CREATE SCHEMA IF NOT EXISTS demo` so the demo connection can create tables inside `demo`.

That migration’s **`up`** does **not** drop or alter anything in `public`. Its **`down`** runs `DROP SCHEMA demo CASCADE`, which removes **only** the `demo` schema (demo data), not production tables.

## `demo_*` tables (second, prefixed copy)

`20260415124532_create_demo_tables.rb` originally introduced a parallel set of **`demo_*`** tables. `20260416110221_drop_demo_tables.rb` removes those names if present.

**`20260515065240_create_demo_table.rb`** creates that **`demo_*` set again**, **in addition to** the normal `users`, `books`, … tables. So each database target ends up with **both** naming styles (e.g. `users` and `demo_users` in the same PostgreSQL schema). Use the normal tables for the app; the `demo_*` set is available for legacy or tooling that still expects those names.

## `demo:reset` (truncate)

`bin/rails demo:reset` truncates tables **only** in the demo target schema (see `lib/tasks/demo.rake`): either schema **`demo`** or **`public`** on the demo-only database. It does **not** truncate `public` on the primary database when demo uses the `demo` schema.

Prefer **`bin/rails demo:reset`** (or `bundle exec rake demo:reset`) so `schema_migrations` / `ar_internal_metadata` stay excluded and the correct schema is used.
