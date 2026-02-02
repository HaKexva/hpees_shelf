class AllowNullNameOnBatches < ActiveRecord::Migration[8.1]
  def change
    change_column_null :batches, :name, true
  end
end
