class Book < ApplicationRecord
  belongs_to :batch_year
  validates :batch_year_id, presence: true
  validates :grade_id, presence: true
end
