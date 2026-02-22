class CreateCirculationRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :circulation_records do |t|
      t.references :book, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamp :borrowed_at, null: false
      t.timestamp :returned_at

      t.timestamps
    end
  end
end
