# frozen_string_literal: true

class CreateTagRuleTables < ActiveRecord::Migration[8.1]
  def change
    create_table :tag_rule_groups do |t|
      t.string :label, default: "未命名", null: false
      t.boolean :required, default: false, null: false
      t.boolean :single_select, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end
    add_index :tag_rule_groups, :position

    create_table :tag_rule_options do |t|
      t.references :tag_rule_group, null: false, foreign_key: true
      t.string :tag_name, default: "", null: false
      t.string :popup_prompt, default: "", null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end
    add_index :tag_rule_options, [:tag_rule_group_id, :position]
  end
end
