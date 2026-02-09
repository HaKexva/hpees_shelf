# frozen_string_literal: true

class AddOptionSourceToTagRuleOptions < ActiveRecord::Migration[8.1]
  def change
    add_column :tag_rule_options, :option_source, :string
  end
end
