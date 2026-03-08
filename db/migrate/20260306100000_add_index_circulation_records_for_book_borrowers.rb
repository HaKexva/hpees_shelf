# frozen_string_literal: true

# When book.total > 1, borrowers are has_many (via circulation_records).
# This index speeds up "active loans per book" (book_id + returned_at nil).
class AddIndexCirculationRecordsForBookBorrowers < ActiveRecord::Migration[8.1]
  def change
    add_index :circulation_records, [ :book_id, :returned_at ],
              name: "index_circulation_records_on_book_id_and_returned_at"
  end
end
