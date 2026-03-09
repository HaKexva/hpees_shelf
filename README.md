# HPEES Shelf

A library management system built with Rails 8.1.

## Dev Environment Setup

### Prerequisites

- Ruby 3.4.8
- PostgreSQL 14+
- Node.js (for asset pipeline)

### Install PostgreSQL

**macOS (Homebrew):**

```bash
brew install postgresql@17
brew services start postgresql@17
```

**Ubuntu/Debian:**

```bash
sudo apt-get install postgresql postgresql-contrib libpq-dev
sudo systemctl start postgresql
```

### Setup

```bash
# Install gems
bundle install

# Create databases and run migrations
bin/rails db:prepare

# Start the dev server
bin/dev
```

### Running Tests

```bash
bin/rails db:test:prepare
bundle exec rspec
```

## Deployment – database

On deploy, **do not clear the database**. Use one of:

* `bin/rails db:prepare` – migrates if the DB exists, or creates and loads schema if it does not (used by Docker entrypoint).
* `bin/rails db:migrate` – only runs pending migrations.

Do **not** use `db:reset`, `db:drop`, or `db:schema:load` in production or in any release/build step; they will wipe existing data.

## Deployment – Railway

1. Add a **PostgreSQL** plugin in your Railway project dashboard.
2. In your Rails app service's **Variables** tab, add: `DATABASE_URL` = `${{Postgres.DATABASE_URL}}`.
3. Push to deploy — `db:prepare` runs automatically via the Docker entrypoint.
