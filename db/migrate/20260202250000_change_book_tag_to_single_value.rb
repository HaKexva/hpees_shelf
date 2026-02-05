# frozen_string_literal: true

class ChangeBookTagToSingleValue < ActiveRecord::Migration[8.1]
  def up
    Book.reset_column_information
    Book.find_each do |book|
      raw = book.read_attribute(:tag)
      next if raw.blank?
      next unless raw.is_a?(String) && raw.strip.start_with?("[")
      parsed = JSON.parse(raw) rescue nil
      single = parsed.is_a?(Array) && parsed.any? ? parsed.first.to_s : raw
      book.update_column(:tag, single)
    end
  end

  def down
    # Reverting would require storing single value as one-element array again; optional
  end
end
