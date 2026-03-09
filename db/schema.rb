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

ActiveRecord::Schema[8.1].define(version: 2026_03_09_121925) do
  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "batch_years", force: :cascade do |t|
    t.integer "batch_number"
    t.datetime "created_at", null: false
    t.integer "entry_month"
    t.integer "entry_year"
    t.integer "grade_id"
    t.boolean "is_office", default: false, null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "books", force: :cascade do |t|
    t.integer "batch_year_id"
    t.datetime "borrowed_at"
    t.string "call_number"
    t.datetime "created_at", null: false
    t.string "edition_part"
    t.integer "grade_id"
    t.string "isbn"
    t.text "note"
    t.integer "source", default: 0, null: false
    t.string "status", default: "架上", null: false
    t.string "title"
    t.integer "total"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "volume"
    t.index ["call_number"], name: "index_books_on_call_number"
    t.index ["user_id"], name: "index_books_on_user_id"
  end

  create_table "circulation_records", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "borrowed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "returned_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["book_id", "returned_at"], name: "index_circulation_records_on_book_id_and_returned_at"
    t.index ["book_id"], name: "index_circulation_records_on_book_id"
    t.index ["user_id"], name: "index_circulation_records_on_user_id"
  end

  create_table "library_loan_histories", force: :cascade do |t|
    t.integer "batch_year_id"
    t.integer "book_id"
    t.string "book_isbn"
    t.string "book_title", null: false
    t.datetime "borrowed_at"
    t.datetime "created_at", null: false
    t.datetime "returned_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_year_id"], name: "index_library_loan_histories_on_batch_year_id"
    t.index ["book_id"], name: "index_library_loan_histories_on_book_id"
  end

  create_table "tag_rule_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", default: "未命名", null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.boolean "single_select", default: true, null: false
    t.string "target", default: "book"
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_tag_rule_groups_on_position"
  end

  create_table "tag_rule_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "option_source"
    t.string "popup_prompt", default: "", null: false
    t.integer "position", default: 0, null: false
    t.string "relocation_behavior"
    t.string "tag_name", default: "", null: false
    t.integer "tag_rule_group_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_rule_group_id", "position"], name: "index_tag_rule_options_on_tag_rule_group_id_and_position"
    t.index ["tag_rule_group_id"], name: "index_tag_rule_options_on_tag_rule_group_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.integer "tag_id"
    t.integer "taggable_id"
    t.string "taggable_type"
    t.integer "tagger_id"
    t.string "tagger_type"
    t.string "tenant", limit: 128
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tagger_type", "tagger_id"], name: "index_taggings_on_tagger_type_and_tagger_id"
    t.index ["tenant"], name: "index_taggings_on_tenant"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "taggings_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.integer "batch_year_id"
    t.datetime "created_at", null: false
    t.string "email"
    t.integer "grade_id"
    t.string "id_number"
    t.boolean "is_office", default: false, null: false
    t.string "name"
    t.datetime "resigned_at"
    t.string "seat_number"
    t.datetime "updated_at", null: false
  end

  create_table "users_batch_years", force: :cascade do |t|
    t.integer "batch_year_id", null: false
    t.integer "user_id", null: false
  end

  add_foreign_key "books", "batch_years"
  add_foreign_key "circulation_records", "books"
  add_foreign_key "circulation_records", "users"
  add_foreign_key "library_loan_histories", "batch_years"
  add_foreign_key "tag_rule_options", "tag_rule_groups"
  add_foreign_key "taggings", "tags"
  add_foreign_key "users", "batch_years"
end
