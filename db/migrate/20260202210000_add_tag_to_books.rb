# frozen_string_literal: true

class AddTagToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :tag, :string
  end
end
