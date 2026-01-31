class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :title
      t.string :isbn
      t.integer :total
      t.integer :volume
      t.text :note
      t.integer :grade_id

      t.timestamps
    end
  end
end
