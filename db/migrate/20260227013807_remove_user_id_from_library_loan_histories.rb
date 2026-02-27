class RemoveUserIdFromLibraryLoanHistories < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :library_loan_histories, :users, if_exists: true
    remove_index :library_loan_histories, name: "index_library_loan_histories_on_user_returned", if_exists: true
    remove_index :library_loan_histories, name: "index_library_loan_histories_on_user_id", if_exists: true
    remove_column :library_loan_histories, :user_id, :integer
  end
end
