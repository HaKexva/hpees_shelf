class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email
      t.string :id_number
      t.string :name
      t.boolean :admin

      t.timestamps
    end
  end
end
