class CreateBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :batches do |t|
      t.string :name, null: false

      t.timestamps
    end
  end
end
