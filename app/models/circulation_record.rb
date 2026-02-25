class CirculationRecord < ApplicationRecord
  belongs_to :book
  belongs_to :user

  validates :user_id, presence: { message: "借閱人不可為空" }
end
