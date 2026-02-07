# frozen_string_literal: true

class RevertBooksTagToStringColumn < ActiveRecord::Migration[8.1]
  def up
    add_column :books, :tag, :string unless column_exists?(:books, :tag)
    # Copy first tag name from taggings/tags into books.tag
    execute <<~SQL.squish
      UPDATE books SET tag = (
        SELECT tags.name FROM taggings
        INNER JOIN tags ON tags.id = taggings.tag_id
        WHERE taggings.taggable_type = 'Book' AND taggings.taggable_id = books.id
        LIMIT 1
      )
    SQL
  end

  def down
    remove_column :books, :tag if column_exists?(:books, :tag)
  end
end
