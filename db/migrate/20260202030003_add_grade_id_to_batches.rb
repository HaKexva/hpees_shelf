class AddGradeIdToBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :batches, :grade_id, :integer
  end
end
