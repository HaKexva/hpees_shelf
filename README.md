# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Deployment – database

On deploy, **do not clear the database**. Use one of:

* `bin/rails db:prepare` – migrates if the DB exists, or creates and loads schema if it does not (used by Docker entrypoint).
* `bin/rails db:migrate` – only runs pending migrations.

Do **not** use `db:reset`, `db:drop`, or `db:schema:load` in production or in any release/build step; they will wipe existing data.
