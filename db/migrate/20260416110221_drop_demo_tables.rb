class DropDemoTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :demo_users_batch_years, if_exists: true
    drop_table :demo_taggings, if_exists: true
    drop_table :demo_tag_rule_options, if_exists: true
    drop_table :demo_tag_rule_groups, if_exists: true
    drop_table :demo_tags, if_exists: true
    drop_table :demo_circulation_records, if_exists: true
    drop_table :demo_library_loan_histories, if_exists: true
    drop_table :demo_books, if_exists: true
    drop_table :demo_batch_years, if_exists: true
    drop_table :demo_users, if_exists: true
    drop_table :demo_app_settings, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
