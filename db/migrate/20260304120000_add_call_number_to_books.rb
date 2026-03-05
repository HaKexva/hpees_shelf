class AddCallNumberToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :call_number, :string
    add_index :books, :call_number
  end
end
