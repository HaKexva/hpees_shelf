class CreateDemoTables < ActiveRecord::Migration[8.1]
  def up
    create_table "demo_app_settings", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "key", null: false
      t.datetime "updated_at", null: false
      t.string "value"
      t.index [ "key" ], name: "index_demo_app_settings_on_key", unique: true
    end

    create_table "demo_batch_years", force: :cascade do |t|
      t.integer "batch_number"
      t.datetime "created_at", null: false
      t.integer "entry_month"
      t.integer "entry_year"
      t.integer "grade_id"
      t.boolean "is_office", default: false, null: false
      t.string "name"
      t.datetime "updated_at", null: false
    end

    create_table "demo_books", force: :cascade do |t|
      t.integer "batch_year_id"
      t.datetime "borrowed_at"
      t.string "call_number"
      t.datetime "created_at", null: false
      t.datetime "deleted_at"
      t.string "edition_part"
      t.integer "grade_id"
      t.string "isbn"
      t.text "note"
      t.string "relocation_behavior", default: "move_with_class", null: false
      t.integer "source", default: 0, null: false
      t.string "status", default: "架上", null: false
      t.string "title"
      t.integer "total"
      t.datetime "updated_at", null: false
      t.bigint "user_id"
      t.string "volume"
      t.index [ "call_number" ], name: "index_demo_books_on_call_number"
      t.index [ "deleted_at" ], name: "index_demo_books_on_deleted_at"
      t.index [ "user_id" ], name: "index_demo_books_on_user_id"
    end

    create_table "demo_circulation_records", force: :cascade do |t|
      t.integer "book_id", null: false
      t.datetime "borrowed_at", null: false
      t.datetime "created_at", null: false
      t.datetime "returned_at"
      t.datetime "updated_at", null: false
      t.integer "user_id", null: false
      t.index [ "book_id", "returned_at" ], name: "index_demo_circulation_records_on_book_id_and_returned_at"
      t.index [ "book_id" ], name: "index_demo_circulation_records_on_book_id"
      t.index [ "user_id" ], name: "index_demo_circulation_records_on_user_id"
    end

    create_table "demo_library_loan_histories", force: :cascade do |t|
      t.integer "batch_year_id"
      t.integer "book_id"
      t.string "book_isbn"
      t.string "book_title", null: false
      t.datetime "borrowed_at"
      t.datetime "created_at", null: false
      t.datetime "returned_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "batch_year_id" ], name: "index_demo_library_loan_histories_on_batch_year_id"
      t.index [ "book_id" ], name: "index_demo_library_loan_histories_on_book_id"
    end

    create_table "demo_tag_rule_groups", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "label", default: "未命名", null: false
      t.integer "position", default: 0, null: false
      t.boolean "required", default: false, null: false
      t.boolean "single_select", default: true, null: false
      t.string "target", default: "book"
      t.datetime "updated_at", null: false
      t.index [ "position" ], name: "index_demo_tag_rule_groups_on_position"
    end

    create_table "demo_tag_rule_options", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "option_source"
      t.string "popup_prompt", default: "", null: false
      t.integer "position", default: 0, null: false
      t.string "relocation_behavior"
      t.string "tag_name", default: "", null: false
      t.integer "tag_rule_group_id", null: false
      t.datetime "updated_at", null: false
      t.index [ "tag_rule_group_id", "position" ], name: "index_demo_tag_rule_options_on_group_and_position"
      t.index [ "tag_rule_group_id" ], name: "index_demo_tag_rule_options_on_tag_rule_group_id"
    end

    create_table "demo_taggings", force: :cascade do |t|
      t.string "context", limit: 128
      t.datetime "created_at", precision: nil
      t.integer "tag_id"
      t.integer "taggable_id"
      t.string "taggable_type"
      t.integer "tagger_id"
      t.string "tagger_type"
      t.string "tenant", limit: 128
      t.index [ "context" ], name: "index_demo_taggings_on_context"
      t.index [ "tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type" ], name: "demo_taggings_idx", unique: true
      t.index [ "tag_id" ], name: "index_demo_taggings_on_tag_id"
      t.index [ "taggable_id", "taggable_type", "context" ], name: "demo_taggings_taggable_context_idx"
      t.index [ "taggable_id", "taggable_type", "tagger_id", "context" ], name: "demo_taggings_idy"
      t.index [ "taggable_id" ], name: "index_demo_taggings_on_taggable_id"
      t.index [ "taggable_type", "taggable_id" ], name: "index_demo_taggings_on_taggable_type_and_taggable_id"
      t.index [ "taggable_type" ], name: "index_demo_taggings_on_taggable_type"
      t.index [ "tagger_id", "tagger_type" ], name: "index_demo_taggings_on_tagger_id_and_tagger_type"
      t.index [ "tagger_id" ], name: "index_demo_taggings_on_tagger_id"
      t.index [ "tagger_type", "tagger_id" ], name: "index_demo_taggings_on_tagger_type_and_tagger_id"
      t.index [ "tenant" ], name: "index_demo_taggings_on_tenant"
    end

    create_table "demo_tags", force: :cascade do |t|
      t.datetime "created_at", null: false
      t.string "name"
      t.integer "taggings_count", default: 0
      t.datetime "updated_at", null: false
      t.index [ "name" ], name: "index_demo_tags_on_name", unique: true
    end

    create_table "demo_users", force: :cascade do |t|
      t.boolean "admin", default: false, null: false
      t.integer "batch_year_id"
      t.datetime "created_at", null: false
      t.datetime "deleted_at"
      t.string "email"
      t.string "google_uid"
      t.integer "grade_id"
      t.string "id_number"
      t.boolean "is_office", default: false, null: false
      t.string "name"
      t.datetime "resigned_at"
      t.string "seat_number"
      t.datetime "updated_at", null: false
      t.index [ "deleted_at" ], name: "index_demo_users_on_deleted_at"
      t.index [ "email" ], name: "index_demo_users_on_email", unique: true
    end

    create_table "demo_users_batch_years", force: :cascade do |t|
      t.integer "batch_year_id", null: false
      t.integer "user_id", null: false
    end
  end

  def down
    drop_table "demo_app_settings"
    drop_table "demo_batch_years"
    drop_table "demo_books"
    drop_table "demo_circulation_records"
    drop_table "demo_library_loan_histories"
    drop_table "demo_tag_rule_groups"
    drop_table "demo_tag_rule_options"
    drop_table "demo_taggings"
    drop_table "demo_tags"
    drop_table "demo_users"
    drop_table "demo_users_batch_years"
  end
end
