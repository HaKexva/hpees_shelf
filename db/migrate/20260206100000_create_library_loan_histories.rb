# frozen_string_literal: true

class CreateLibraryLoanHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :library_loan_histories do |t|
      t.references :user, null: true, foreign_key: true
      t.string :book_title, null: false
      t.string :book_isbn
      t.datetime :borrowed_at
      t.datetime :returned_at, null: false
      t.references :batch_year, null: true, foreign_key: true

      t.timestamps
    end
    add_index :library_loan_histories, [ :user_id, :returned_at ], name: "index_library_loan_histories_on_user_returned"
  end
end
