class AddBatchYearIdBackToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :batch_year_id, :integer
    add_foreign_key :users, :batch_years, column: :batch_year_id
  end
end

