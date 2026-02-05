class User < ApplicationRecord
  # Primary batch_year: every user (student or admin) still belongs to one main batch_year
  belongs_to :batch_year

  # Extra batch years for admins (teachers) who may be linked to multiple cohorts/classes
  has_and_belongs_to_many :extra_batch_years,
                          class_name: "BatchYear",
                          join_table: "users_batch_years"
  before_save :sync_is_office_from_batch_year
  before_save :sync_grade_id_from_batch_year

  scope :active, -> { where(resigned_at: nil) }

  def resigned?
    resigned_at.present?
  end

  def office_teacher?
    batch_year&.is_office? || is_office?
  end

  private

  def sync_is_office_from_batch_year
    self.is_office = (batch_year&.is_office? == true)
    # Everyone in the office (teacher batch) must be an admin
    self.admin = true if batch_year&.is_office?
  end

  # Teacher batch (office) has no grade_id; class batches copy batch_year.grade_id
  def sync_grade_id_from_batch_year
    return unless batch_year
    self.grade_id = batch_year.is_office? ? nil : batch_year.grade_id
  end
end
