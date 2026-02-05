class AddBatchIdToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :batch, null: true, foreign_key: true
  end
end
