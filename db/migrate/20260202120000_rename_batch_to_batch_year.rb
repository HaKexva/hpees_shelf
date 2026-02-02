# frozen_string_literal: true

class RenameBatchToBatchYear < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :books, :batches
    remove_foreign_key :users, :batches
    remove_index :books, :batch_id
    remove_index :users, :batch_id

    rename_column :books, :batch_id, :batch_year_id
    rename_column :users, :batch_id, :batch_year_id
    rename_table :batches, :batch_years

    add_foreign_key :books, :batch_years, column: :batch_year_id
    add_foreign_key :users, :batch_years, column: :batch_year_id
  end
end
