# frozen_string_literal: true

class ConvertBookTagToJsonArray < ActiveRecord::Migration[8.1]
  def up
    Book.reset_column_information
    Book.find_each do |book|
      raw = book.read_attribute(:tag)
      next if raw.blank?
      next if raw.is_a?(String) && raw.strip.start_with?("[")
      arr = [raw].to_json
      book.update_column(:tag, arr)
    end
  end

  def down
    Book.reset_column_information
    Book.find_each do |book|
      raw = book.read_attribute(:tag)
      next if raw.blank?
      next unless raw.is_a?(String) && raw.strip.start_with?("[")
      parsed = JSON.parse(raw) rescue nil
      single = parsed.is_a?(Array) && parsed.one? ? parsed.first : raw
      book.update_column(:tag, single)
    end
  end
end
