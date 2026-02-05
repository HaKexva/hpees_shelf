# frozen_string_literal: true

class RenameBatchYearToInNeed < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :books, :batch_years
    remove_foreign_key :users, :batch_years

    rename_column :books, :batch_year_id, :in_need_id
    rename_column :users, :batch_year_id, :in_need_id
    rename_table :batch_years, :in_needs

    add_foreign_key :books, :in_needs, column: :in_need_id
    add_foreign_key :users, :in_needs, column: :in_need_id
  end
end
