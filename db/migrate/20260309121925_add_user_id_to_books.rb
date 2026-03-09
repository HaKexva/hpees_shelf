class AddUserIdToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :user_id, :bigint
    add_index :books, :user_id
  end
end
