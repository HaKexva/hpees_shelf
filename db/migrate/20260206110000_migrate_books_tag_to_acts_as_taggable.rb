# frozen_string_literal: true

class MigrateBooksTagToActsAsTaggable < ActiveRecord::Migration[8.1]
  def up
    return unless column_exists?(:books, :tag)

    Book.reset_column_information
    Book.find_each do |book|
      tag_value = book.read_attribute(:tag)
      next if tag_value.blank?
      book.tag_list = [ tag_value ]
      book.save(validate: false)
    end

    remove_column :books, :tag
  end

  def down
    add_column :books, :tag, :string unless column_exists?(:books, :tag)
    Book.reset_column_information
    Book.find_each do |book|
      next if book.tag_list.empty?
      book.write_attribute(:tag, book.tag_list.first)
      book.save(validate: false)
    end
    # Clear taggings for Book so we don't leave orphaned records when rolling back again
    execute <<~SQL.squish
      DELETE FROM taggings WHERE taggable_type = 'Book'
    SQL
  end
end
