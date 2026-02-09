# frozen_string_literal: true

class BooksUseActsAsTaggableTags < ActiveRecord::Migration[8.1]
  def up
    return unless column_exists?(:books, :tag)

    require "acts-as-taggable-on"
    Book.reset_column_information
    Book.find_each do |book|
      tag_value = book.read_attribute(:tag).to_s.strip
      next if tag_value.blank?

      tag = ActsAsTaggableOn::Tag.find_or_create_by!(name: tag_value)
      ActsAsTaggableOn::Tagging.find_or_create_by!(
        tag_id: tag.id,
        taggable_type: "Book",
        taggable_id: book.id,
        context: "tags"
      )
    end
    remove_column :books, :tag
  end

  def down
    add_column :books, :tag, :string unless column_exists?(:books, :tag)
    Book.reset_column_information
    Book.find_each do |book|
      list = book.tag_list
      next if list.empty?

      book.write_attribute(:tag, list.first)
      book.save(validate: false)
    end
    execute <<~SQL.squish
      DELETE FROM taggings WHERE taggable_type = 'Book'
    SQL
  end
end
