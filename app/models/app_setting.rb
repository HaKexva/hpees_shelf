# frozen_string_literal: true

class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  class << self
    def get(key)
      find_by(key: key)&.value
    end

    def set(key, value)
      record = find_or_initialize_by(key: key)
      record.update!(value: value.to_s)
      value
    end
  end
end
