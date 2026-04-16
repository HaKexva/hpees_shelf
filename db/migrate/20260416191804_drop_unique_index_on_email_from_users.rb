class DropUniqueIndexOnEmailFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, :email, if_exists: true
  end
end
