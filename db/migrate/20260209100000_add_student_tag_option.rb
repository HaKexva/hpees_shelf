# frozen_string_literal: true

class AddStudentTagOption < ActiveRecord::Migration[8.1]
  def up
    return unless defined?(TagRuleGroup) && defined?(TagRuleOption)
    first_group = TagRuleGroup.order(:position).first
    return unless first_group
    return if first_group.tag_rule_options.exists?(tag_name: "學生的書")
    max_pos = first_group.tag_rule_options.maximum(:position).to_i
    first_group.tag_rule_options.create!(
      tag_name: "學生的書",
      popup_prompt: "",
      position: max_pos + 1
    )
  end

  def down
    return unless defined?(TagRuleOption)
    TagRuleOption.where(tag_name: "學生的書").destroy_all
  end
end
