class CreateUsersBatchYears < ActiveRecord::Migration[8.1]
  def change
    create_table :users_batch_years do |t|
      t.integer :user_id, null: false
      t.integer :batch_year_id, null: false
    end
  end
end
