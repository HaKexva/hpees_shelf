class DeleteZeroBatchYears < ActiveRecord::Migration[8.1]
  def up
    say_with_time "Deleting batch_years with batch_number = 0" do
      batch_year_ids = execute("SELECT id FROM batch_years WHERE batch_number = 0").pluck("id")
      next 0 if batch_year_ids.empty?

      ids = batch_year_ids.join(",")
      execute("UPDATE books SET batch_year_id = NULL WHERE batch_year_id IN (#{ids})")
      execute("UPDATE users SET batch_year_id = NULL WHERE batch_year_id IN (#{ids})")
      execute("DELETE FROM batch_years WHERE id IN (#{ids})")
      batch_year_ids.size
    end
  end

  def down
    # no-op: we don't recreate the \"第0屆\" row once deleted
  end
end
