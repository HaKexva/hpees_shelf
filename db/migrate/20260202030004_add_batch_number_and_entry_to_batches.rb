class AddBatchNumberAndEntryToBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :batches, :batch_number, :integer
    add_column :batches, :entry_year, :integer
    add_column :batches, :entry_month, :integer
  end
end
