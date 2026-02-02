# frozen_string_literal: true

class RenameInNeedIdBackToGradeId < ActiveRecord::Migration[8.1]
  def change
    rename_column :batch_years, :in_need_id, :grade_id
    rename_column :books, :in_need_id, :grade_id
  end
end
