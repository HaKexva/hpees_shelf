# frozen_string_literal: true

class AddRelocationBehaviorToBooks < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:books, :relocation_behavior)

    add_column :books, :relocation_behavior, :string, null: false, default: "move_with_class"
  end

  def down
    remove_column :books, :relocation_behavior if column_exists?(:books, :relocation_behavior)
  end
end
