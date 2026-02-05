# frozen_string_literal: true

class AddSeatNumberToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :seat_number, :string
  end
end
