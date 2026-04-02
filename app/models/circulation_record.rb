class CirculationRecord < ApplicationRecord
  belongs_to :book, -> { merge(Book.with_deleted) }, inverse_of: :circulation_records
  belongs_to :user

  validates :user_id, presence: { message: "借閱人不可為空" }
end
