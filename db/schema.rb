# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_02_140100) do
  create_table "books", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "grade_id"
    t.integer "in_need_id"
    t.string "isbn"
    t.text "note"
    t.string "title"
    t.integer "total"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "volume"
    t.index ["user_id"], name: "index_books_on_user_id"
  end

  create_table "in_needs", force: :cascade do |t|
    t.integer "batch_number"
    t.datetime "created_at", null: false
    t.integer "entry_month"
    t.integer "entry_year"
    t.integer "grade_id"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "id_number"
    t.integer "in_need_id"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "books", "in_needs"
  add_foreign_key "books", "users"
  add_foreign_key "users", "in_needs"
end
