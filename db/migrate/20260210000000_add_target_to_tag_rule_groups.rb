# frozen_string_literal: true

class AddTargetToTagRuleGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :tag_rule_groups, :target, :string, default: "book"
  end
end
