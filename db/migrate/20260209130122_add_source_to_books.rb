class AddSourceToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :source, :integer, default: 0, null: false
  end
end
