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

Demo mode uses a **second Active Record shard** (`:demo`) and prefixes all routes with `/demo`. On the default setup, the shard shares **`DATABASE_URL`** with primary and stores a **full duplicate of the schema** in the PostgreSQL schema **`demo`** (`demo.users`, `demo.books`, …); `public.*` stays the live app data.

- **Enable**: set `DEMO_ENABLED=true`
- **Entry point**: visit `/demo` (auto-login as demo admin)
- **Optional**: set `DEMO_DATABASE_URL` to a **separate** Postgres database instead; migrations and data then use `public` on that database (no `demo` schema needed there).
- After deploying schema changes, run migrations (e.g. deploy entrypoint `db:migrate`) so **both** primary and `primary_shard_demo` stay in sync.
- **How this maps to migrations** (no `CREATE DATABASE` in Rails): see [docs/DEMO_SHARD.md](docs/DEMO_SHARD.md).


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

展示模式會把所有路徑加上 `/demo` 前綴，並使用 **另一個 Active Record shard（`:demo`）**。預設與正式環境共用 **`DATABASE_URL`**（同一個 Postgres 資料庫），示範資料放在 PostgreSQL schema **`demo`**（與 `public.*` 一組對一組的**重複資料表**，例如 `demo.users`）；正式資料仍在 `public`。

- **啟用**：設定 `DEMO_ENABLED=true`
- **入口**：瀏覽 `/demo`（自動以示範管理員登入）
- **選用**：設定 `DEMO_DATABASE_URL` 指向**另一個** Postgres 資料庫時，示範資料改存在該库的 `public`（不必再用 `demo` schema）。
- 部署後請讓 migration 跑滿 **primary** 與 **primary_shard_demo**（例如 entrypoint 的 `db:migrate`）。
- **與 migration 的對應**（Rails 不會在 migration 裡 `CREATE DATABASE`）：見 [docs/DEMO_SHARD.md](docs/DEMO_SHARD.md)。