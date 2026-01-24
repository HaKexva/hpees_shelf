class ChangeUsersColumns < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :admin, false, false
    change_column_default :users, :admin, from: nil, to: false
  end
end
