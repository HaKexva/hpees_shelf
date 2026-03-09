# HPEES Shelf

A library management system built with Rails 8.1.

## Dev Environment Setup

### Prerequisites

- Ruby 3.4.8 (see `.ruby-version`)
- PostgreSQL 17

### 1. Install PostgreSQL

**macOS (Homebrew):**

```bash
brew install postgresql@17
```

After installation, follow the instructions printed by Homebrew to add PostgreSQL to your PATH. Typically:

```bash
echo 'export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Then start the service:

```bash
brew services start postgresql@17
```

**Ubuntu/Debian:**

```bash
sudo apt-get install postgresql postgresql-contrib libpq-dev
sudo systemctl start postgresql
```

### 2. Install Gems

```bash
bundle install
```

### 3. Create Database and Run Migrations

```bash
bin/rails db:prepare
```

This creates `hpees_shelf_development` and runs all pending migrations.

### 4. Start the Dev Server

```bash
bin/dev
```

Visit `http://localhost:3000`.

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
