# HPEES Shelf · 圖書管理系統

School library and circulation management for **books**, **users (students / staff)**, and **batch years (屆數 / 學年)**. Default UI locale is **Traditional Chinese (`zh-TW`)**; default time zone is **`Asia/Taipei`**.

| | |
|---:|---|
| **English** | [Table of contents (EN)](#table-of-contents-english) |
| **繁體中文** | [中文目錄](#目錄中文) |

---

## Table of contents (English)

1. [Overview](#overview)
2. [Tech stack](#tech-stack)
3. [Domain concepts](#domain-concepts)
4. [Main areas of the app](#main-areas-of-the-app)
5. [Local development setup](#local-development-setup)
6. [Running tests](#running-tests)
7. [Background jobs (Solid Queue)](#background-jobs-solid-queue)
8. [Assets, Tailwind CSS, and import maps](#assets-tailwind-css-and-import-maps)
9. [Deployment – database](#deployment--database)
10. [Deployment – Railway](#deployment--railway)
11. [Docker and Kamal](#docker-and-kamal)

---

## 目錄（中文）

1. [專案概要](#專案概要)
2. [技術棧](#技術棧)
3. [網域概念](#網域概念)
4. [主要功能區](#主要功能區)
5. [本機開發環境](#本機開發環境)
6. [執行測試](#執行測試)
7. [背景工作（Solid Queue）](#背景工作solid-queue)
8. [前端資源](#前端資源)
9. [部署：資料庫](#部署資料庫)
10. [部署：Railway](#部署railway)
11. [Docker 與 Kamal](#docker-與-kamal)

---

## Overview

HPEES Shelf is a **Rails 8.1** monolith for a school library: cataloging books, tracking **屆數** (cohort / batch years), managing **users**, **borrow/return** flows, **CSV import/export**, **inventory PDFs**, and **school-year** batch transitions. Admin-facing UI is primarily in **Traditional Chinese**.

### 專案概要

本專案為學校圖書／流通管理後台：書籍、人員（屆數／年級）、借還、匯入匯出、盤點與學年度屆數切換等。介面預設為**繁體中文**。

---

## Tech stack

- **Ruby** 3.4.x (see `.ruby-version`)
- **Rails** 8.1
- **PostgreSQL** (development, test, production)
- **Hotwire**: Turbo + Stimulus; **importmap** for JavaScript
- **Propshaft** + **Tailwind CSS** (`tailwindcss-rails`)
- **Solid Queue** / **Solid Cache** / **Solid Cable** (Rails defaults)
- **Kamal** + **Thruster** (optional container deployment)
- **RSpec** + **RuboCop** (Rails Omakase style)

### 技術棧

Ruby on Rails 8、PostgreSQL、Hotwire（Turbo / Stimulus）、Tailwind、Solid Queue 等，詳見 `Gemfile`。

---

## Domain concepts

- **Batch year (`batch_year`, 屆數)** — Cohort / school year bucket; drives grade display and relocation after year rollover.
- **Book** — Title, ISBN-13, source (library / donated / class / teacher), optional **班級書** relocation mode for class-owned copies, circulation status, soft delete.
- **User** — Students and staff; links to batch year and grade where applicable.
- **Circulation** — Borrow / return and related records.

### 網域概念

**屆數**、**書籍**（含來源與班級書切換）、**使用者**、**借閱流通**等。

---

## Main areas of the app

- **Books** — List filters, CSV export, import with preview, inventory PDF, bulk delete (soft).
- **Users** — CRUD, import, batch year assignment.
- **Batch years** — Index, auto-create range, **advance school year** and relocation flow for graduated batches.
- **Authentication** — Session-based login for admins (see `User` model and sessions controller).

### 主要功能區

書籍、使用者、屆數管理、學年度切換與指定屆數、登入驗證等。

---

## Local development setup

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

### 2. Install gems

```bash
bundle install
```

### 3. Create database and run migrations

```bash
bin/rails db:prepare
```

This creates `hpees_shelf_development` and runs all pending migrations.

### 4. Start the dev server

```bash
bin/dev
```

This runs the Rails server and `tailwindcss:watch` (see `Procfile.dev`). Visit `http://localhost:3000`.

### 本機開發環境

安裝 Ruby、PostgreSQL 後執行 `bundle install`、`bin/rails db:prepare`，再以 `bin/dev` 啟動。

---

## Running tests

```bash
bin/rails db:test:prepare
bundle exec rspec
```

Lint (project convention):

```bash
bundle exec rubocop
```

### 執行測試

使用 RSpec；提交前可執行 RuboCop。

---

## Background jobs (Solid Queue)

The app uses **Solid Queue** (see `config/solid_queue.yml` and `db/queue_schema.rb`). In development, enqueue processing as needed for your workflow (e.g. run a Solid Queue supervisor if you exercise async jobs).

### 背景工作（Solid Queue）

依 Rails 8 預設整合 Solid Queue，細節見設定檔。

---

## Assets, Tailwind CSS, and import maps

- **Styles**: Tailwind via `tailwindcss-rails`; watch with `bin/rails tailwindcss:watch` (included in `bin/dev`).
- **JavaScript**: `importmap-rails` + Stimulus controllers under `app/javascript/controllers`.

### 前端資源

Tailwind 與 importmap／Stimulus，見 `app/assets` 與 `app/javascript`。

---

## Deployment – database

On deploy, **do not clear the database**. Use one of:

* `bin/rails db:prepare` — migrates if the DB exists, or creates and loads schema if it does not (used by the Docker entrypoint).
* `bin/rails db:migrate` — only runs pending migrations.

Do **not** use `db:reset`, `db:drop`, or `db:schema:load` in production or in any release/build step; they will wipe existing data.

### 部署：資料庫

正式環境請使用 `db:prepare` 或 `db:migrate`，避免會清空資料的指令。

---

## Deployment – Railway

1. Add a **PostgreSQL** plugin in your Railway project dashboard.
2. In your Rails app service's **Variables** tab, add: `DATABASE_URL` = `${{Postgres.DATABASE_URL}}`.
3. Push to deploy — `db:prepare` runs automatically via the Docker entrypoint.

### 部署：Railway

建立 PostgreSQL 外掛、設定 `DATABASE_URL`，部署時 entrypoint 會執行 `db:prepare`。

---

## Docker and Kamal

- **Dockerfile** — Production-oriented image; build with `docker build -t hpees_shelf .` (see comments at top of `Dockerfile`).
- **Kamal** — Optional; see `config/deploy.yml` and [Kamal](https://kamal-deploy.org) documentation.

### Docker 與 Kamal

詳見專案根目錄 `Dockerfile` 與 Kamal 設定。

---

## Contributing / AI workflow

For maintainers: see **`AGENTS.md`** (Cursor / Linear / branch → PR → merge to `main`). Do not push feature work directly to `main`.
