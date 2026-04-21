# HPEES Shelf

**Language  語言:** [English](#readme-en) · [繁體中文](#readme-zh)

---

<a id="readme-en"></a>

## English

School library and circulation management for **books**, **users (students / staff)**, and **batch years (屆數 / 學年)**. The app defaults to **Traditional Chinese (`zh-TW`)** for the UI and **`Asia/Taipei`** for the time zone.

### Table of contents

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
12. [Contributing / AI workflow](#contributing--ai-workflow)

### Overview

HPEES Shelf is a **Rails 8.1** monolith for a school library: cataloging books, tracking **屆數** (cohort / batch years), managing **users**, **borrow/return** flows, **CSV import/export**, **inventory PDFs**, and **school-year** batch transitions. Admin-facing UI is primarily in **Traditional Chinese**.

### Tech stack

- **Ruby** 3.4.x (see `.ruby-version`)
- **Rails** 8.1
- **PostgreSQL** (development, test, production)
- **Hotwire**: Turbo + Stimulus; **importmap** for JavaScript
- **Propshaft** + **Tailwind CSS** (`tailwindcss-rails`)
- **Solid Queue** / **Solid Cache** / **Solid Cable** (Rails defaults)
- **Kamal** + **Thruster** (optional container deployment)
- **RSpec** + **RuboCop** (Rails Omakase style)

### Domain concepts

- **Batch year (`batch_year`, 屆數)** — Cohort / school year bucket; drives grade display and relocation after year rollover.
- **Book** — Title, ISBN-13, source (library / donated / class / teacher), optional **班級書** relocation mode for class-owned copies, circulation status, soft delete.
- **User** — Students and staff; links to batch year and grade where applicable.
- **Circulation** — Borrow / return and related records.

### Main areas of the app

- **Books** — List filters, CSV export, import with preview, inventory PDF, bulk delete (soft).
- **Users** — CRUD, import, batch year assignment.
- **Batch years** — Index, auto-create range, **advance school year** and relocation flow for graduated batches.
- **Authentication** — Session-based login for admins (see `User` model and sessions controller).

### Demo mode (`/demo`)

Demo mode runs the app against a **separate demo database shard** and prefixes all routes with `/demo`.

- **Enable**: set `DEMO_ENABLED=true`
- **Entry point**: visit `/demo/demo_login` (auto-login as demo admin)
- **Production demo DB**: set `DEMO_DATABASE_URL` (falls back to `DATABASE_URL` if unset)

### Local development setup

#### Prerequisites

- Ruby 3.4.8 (see `.ruby-version`)
- PostgreSQL 17

#### 1. Install PostgreSQL

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

#### 2. Install gems

```bash
bundle install
```

#### 3. Create database and run migrations

```bash
bin/rails db:prepare
```

This creates `hpees_shelf_development` and runs all pending migrations.

#### 4. Start the dev server

```bash
bin/dev
```

This runs the Rails server and `tailwindcss:watch` (see `Procfile.dev`). Visit `http://localhost:3000`.

### Running tests

```bash
bin/rails db:test:prepare
bundle exec rspec
```

Lint (project convention):

```bash
bundle exec rubocop
```

### Background jobs (Solid Queue)

The app uses **Solid Queue** (see `config/solid_queue.yml` and `db/queue_schema.rb`). In development, enqueue processing as needed for your workflow (e.g. run a Solid Queue supervisor if you exercise async jobs).

### Assets, Tailwind CSS, and import maps

- **Styles**: Tailwind via `tailwindcss-rails`; watch with `bin/rails tailwindcss:watch` (included in `bin/dev`).
- **JavaScript**: `importmap-rails` + Stimulus controllers under `app/javascript/controllers`.

### Deployment – database

On deploy, **do not clear the database**. Use one of:

* `bin/rails db:prepare` — migrates if the DB exists, or creates and loads schema if it does not (used by the Docker entrypoint).
* `bin/rails db:migrate` — only runs pending migrations.

Do **not** use `db:reset`, `db:drop`, or `db:schema:load` in production or in any release/build step; they will wipe existing data.

### Deployment – Railway

1. Add a **PostgreSQL** plugin in your Railway project dashboard.
2. In your Rails app service's **Variables** tab, add: `DATABASE_URL` = `${{Postgres.DATABASE_URL}}`.
3. Push to deploy — `db:prepare` runs automatically via the Docker entrypoint.

### Docker and Kamal

- **Dockerfile** — Production-oriented image; build with `docker build -t hpees_shelf .` (see comments at top of `Dockerfile`).
- **Kamal** — Optional; see `config/deploy.yml` and [Kamal](https://kamal-deploy.org) documentation.

### Contributing / AI workflow

For maintainers: see **`AGENTS.md`** (Cursor / Linear / branch → PR → merge to `main`). Do not push feature work directly to `main`.

**Continue:** [繁體中文](#readme-zh)

---

<a id="readme-zh"></a>

## 繁體中文

學校圖書與流通管理：**書籍**、**使用者（學生／教職員）**、**屆數（學年／年級）**。介面預設語系為 **`zh-TW`**，時區為 **`Asia/Taipei`**。

**返回語言選擇：** [English](#readme-en) · [繁體中文](#readme-zh)

### 快速連結

| | |
|:---|:---|
| **線上試用** | *尚未提供公開網址。* 請本機執行 `bin/dev`（見[本機開發環境](#本機開發環境)）或自行部署（如 [Railway](#部署railway)），有網址後可更新此列與 repo **About → Website**。 |
| **原始碼** | [https://github.com/HaKexva/hpees_shelf](https://github.com/HaKexva/hpees_shelf) |
| **GitHub 上的 README** | [在 `main` 檢視 `README.md`](https://github.com/HaKexva/hpees_shelf/blob/main/README.md) |
| **複製儲存庫** | `git clone https://github.com/HaKexva/hpees_shelf.git` |
| **開發紀錄** | [docs/DEVLOG.md](docs/DEVLOG.md)（有日期的紀錄） |

儲存庫需為 **Public**，匿名使用者才能 `git clone`、開啟上述連結。擁有者：**Settings → General → Danger zone → Change repository visibility → Public**。

### 目錄

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
12. [貢獻與工作流程](#貢獻與工作流程)

### 專案概要

本專案為學校圖書／流通管理後台：書籍、人員（屆數／年級）、借還、匯入匯出、盤點與學年度屆數切換等。介面預設為**繁體中文**。

### 技術棧

- **Ruby** 3.4.x（見 `.ruby-version`）
- **Rails** 8.1
- **PostgreSQL**（開發、測試、正式）
- **Hotwire**（Turbo、Stimulus）與 **importmap**
- **Propshaft**、**Tailwind CSS**（`tailwindcss-rails`）
- **Solid Queue**／**Solid Cache**／**Solid Cable**
- **Kamal**、**Thruster**（選用，容器部署）
- **RSpec**、**RuboCop**

詳見 `Gemfile`。

### 網域概念

- **屆數（`batch_year`）** — 學年／年級所屬批次；影響畢業後指定屆數與年級顯示。
- **書籍** — 書名、ISBN-13、來源（圖書館／捐贈／班級／老師）、班級書可選**留班／隨班**、流通狀態、軟刪除。
- **使用者** — 學生與教職員；可連結屆數與年級。
- **借閱流通** — 借出、歸還與相關紀錄。

### 主要功能區

- **書籍** — 列表篩選、CSV 匯出、匯入預覽、盤點 PDF、批次軟刪除。
- **使用者** — CRUD、匯入、屆數指定。
- **屆數** — 列表、一鍵建立屆數、**切換學年度**與畢業屆之指定屆數流程。
- **驗證** — 管理員以 Session 登入（見 `User` 與 sessions 相關程式）。

### 展示模式（`/demo`）

展示模式會把所有路徑加上 `/demo` 前綴，並切換到 **獨立的 demo 資料庫 shard**。

- **啟用**：設定 `DEMO_ENABLED=true`
- **入口**：瀏覽 `/demo/demo_login`（自動以示範管理員登入）
- **正式環境 demo DB**：設定 `DEMO_DATABASE_URL`（未設定則 fallback 到 `DATABASE_URL`）

### 本機開發環境

#### 前置需求

- Ruby 3.4.8（見 `.ruby-version`）
- PostgreSQL 17

#### 1. 安裝 PostgreSQL

**macOS（Homebrew）：**

```bash
brew install postgresql@17
```

依 Homebrew 說明將 `postgresql@17` 加入 `PATH`，例如：

```bash
echo 'export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

啟動服務：

```bash
brew services start postgresql@17
```

**Ubuntu／Debian：**

```bash
sudo apt-get install postgresql postgresql-contrib libpq-dev
sudo systemctl start postgresql
```

#### 2. 安裝 Gem

```bash
bundle install
```

#### 3. 建立資料庫並執行 migration

```bash
bin/rails db:prepare
```

會建立 `hpees_shelf_development` 並套用 migration。

#### 4. 啟動開發伺服器

```bash
bin/dev
```

會同時跑 Rails 與 `tailwindcss:watch`（見 `Procfile.dev`）。瀏覽器開啟 `http://localhost:3000`。

### 執行測試

```bash
bin/rails db:test:prepare
bundle exec rspec
```

程式風格檢查：

```bash
bundle exec rubocop
```

### 背景工作（Solid Queue）

專案使用 **Solid Queue**（見 `config/solid_queue.yml`、`db/queue_schema.rb`）。本機若需實際跑非同步工作，請依需求啟動對應的 queue 處理程序。

### 前端資源

- **樣式**：Tailwind（`tailwindcss-rails`）；`bin/dev` 已含 `tailwindcss:watch`。
- **JavaScript**：`importmap-rails` 與 `app/javascript/controllers` 下的 Stimulus。

### 部署：資料庫

正式環境**請勿清空資料庫**。請使用：

* `bin/rails db:prepare` — 已有 DB 則 migrate；沒有則建立並載入 schema（Docker entrypoint 使用此指令）。
* `bin/rails db:migrate` — 僅執行尚未套用的 migration。

**請勿**在正式環境或 release 流程使用 `db:reset`、`db:drop`、`db:schema:load` 等會刪除資料的指令。

### 部署：Railway

1. 在 Railway 專案中新增 **PostgreSQL** 外掛。
2. 在 Rails 服務的 **Variables** 設定 `DATABASE_URL` = `${{Postgres.DATABASE_URL}}`。
3. 推送部署後，entrypoint 會自動執行 `db:prepare`。

### Docker 與 Kamal

- **Dockerfile** — 正式環境映像；可 `docker build -t hpees_shelf .`（見檔案開頭註解）。
- **Kamal** — 選用；見 `config/deploy.yml` 與 [Kamal 文件](https://kamal-deploy.org)。

### 貢獻與工作流程

維護者請閱讀 **`AGENTS.md`**（Cursor／Linear／分支 → PR → 合併至 `main`）。請勿將功能開發直接推上 `main`。
