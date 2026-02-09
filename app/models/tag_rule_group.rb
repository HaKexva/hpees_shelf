# frozen_string_literal: true

class TagRuleGroup < ApplicationRecord
  has_many :tag_rule_options, -> { order(:position) }, dependent: :destroy

  validates :label, presence: true
end
