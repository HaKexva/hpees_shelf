# frozen_string_literal: true

# Creates the PostgreSQL schema used by the :demo shard when it shares DATABASE_URL
# with primary (`schema_search_path: demo`). Must run before any migration that
# creates tables on the demo connection.
#
# This does NOT create a new PostgreSQL database, drop, or alter `public` tables.
# `up` only ensures schema `demo` exists. `down` drops schema `demo` and everything
# inside it (demo copy only).
class EnsureDemoSchema < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE SCHEMA IF NOT EXISTS demo"
  end

  def down
    execute "DROP SCHEMA IF EXISTS demo CASCADE"
  end
end
