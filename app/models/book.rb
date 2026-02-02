class Book < ApplicationRecord
  belongs_to :batch_year
  validates :batch_year_id, presence: true

  before_validation :set_total_to_one_if_blank

  private

  def set_total_to_one_if_blank
    self.total = 1 if total.blank?
  end
end
