# frozen_string_literal: true

class AddResignedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :resigned_at, :datetime
  end
end
