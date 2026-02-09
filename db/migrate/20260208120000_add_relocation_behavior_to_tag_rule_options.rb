# frozen_string_literal: true

class AddRelocationBehaviorToTagRuleOptions < ActiveRecord::Migration[8.1]
  def change
    add_column :tag_rule_options, :relocation_behavior, :string
  end
end
