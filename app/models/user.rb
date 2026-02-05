class User < ApplicationRecord
  belongs_to :batch_year
  validates :batch_year_id, presence: true

  before_save :sync_is_office_from_batch_year
  before_save :sync_grade_id_from_batch_year

  def office_teacher?
    batch_year&.is_office? || is_office?
  end

  private

  def sync_is_office_from_batch_year
    self.is_office = (batch_year&.is_office? == true)
  end

  # 老師屆數（辦公室）無 grade_id；班級屆數則同步 batch_year.grade_id
  def sync_grade_id_from_batch_year
    return unless batch_year
    self.grade_id = batch_year.is_office? ? nil : batch_year.grade_id
  end
end
