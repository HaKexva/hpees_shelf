class DropBatchYearIdInUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :batch_year_id
  end
end
