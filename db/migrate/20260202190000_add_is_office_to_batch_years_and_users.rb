# frozen_string_literal: true

class AddIsOfficeToBatchYearsAndUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :batch_years, :is_office, :boolean, default: false, null: false
    add_column :users, :is_office, :boolean, default: false, null: false
  end
end
