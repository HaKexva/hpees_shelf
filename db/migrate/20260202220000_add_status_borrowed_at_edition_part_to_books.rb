# frozen_string_literal: true

class AddStatusBorrowedAtEditionPartToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :status, :string, default: "on_shelf", null: false
    add_column :books, :borrowed_at, :datetime
    add_column :books, :edition_part, :string
  end
end
