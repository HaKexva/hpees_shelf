# frozen_string_literal: true

class RenameGradeIdToInNeedId < ActiveRecord::Migration[8.1]
  def change
    rename_column :batch_years, :grade_id, :in_need_id
    rename_column :books, :grade_id, :in_need_id
  end
end
