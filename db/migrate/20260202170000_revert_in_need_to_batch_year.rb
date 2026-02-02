# frozen_string_literal: true

class RevertInNeedToBatchYear < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :books, :in_needs
    remove_foreign_key :users, :in_needs

    rename_column :books, :in_need_id, :batch_year_id
    rename_column :users, :in_need_id, :batch_year_id
    rename_table :in_needs, :batch_years

    add_foreign_key :books, :batch_years, column: :batch_year_id
    add_foreign_key :users, :batch_years, column: :batch_year_id
  end
end
