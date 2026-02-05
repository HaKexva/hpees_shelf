# frozen_string_literal: true

class AddGradeIdToUsersAndRenameOfficeToTeacher < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :grade_id, :integer
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE batch_years SET name = '老師' WHERE is_office = true
        SQL
      end
    end
  end
end
