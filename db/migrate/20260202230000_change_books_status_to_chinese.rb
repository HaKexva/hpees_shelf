# frozen_string_literal: true

class ChangeBooksStatusToChinese < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL.squish
      UPDATE books SET status = '架上' WHERE status = 'on_shelf';
    SQL
    execute <<-SQL.squish
      UPDATE books SET status = '借閱中' WHERE status = 'borrowed';
    SQL
    execute <<-SQL.squish
      UPDATE books SET status = '失蹤' WHERE status = 'missing';
    SQL
    change_column_default :books, :status, from: "on_shelf", to: "架上"
  end

  def down
    execute <<-SQL.squish
      UPDATE books SET status = 'on_shelf' WHERE status = '架上';
    SQL
    execute <<-SQL.squish
      UPDATE books SET status = 'borrowed' WHERE status = '借閱中';
    SQL
    execute <<-SQL.squish
      UPDATE books SET status = 'missing' WHERE status = '失蹤';
    SQL
    change_column_default :books, :status, from: "架上", to: "on_shelf"
  end
end
