class AddBookIdToLibraryLoanHistories < ActiveRecord::Migration[8.1]
  def change
    add_column :library_loan_histories, :book_id, :integer
    add_index :library_loan_histories, :book_id
  end
end
