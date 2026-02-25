class ChangeBooksVolumeToString < ActiveRecord::Migration[8.1]
  def up
    change_column :books, :volume, :string
  end

  def down
    change_column :books, :volume, :integer
  end
end

