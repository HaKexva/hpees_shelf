class User < ApplicationRecord
  # Primary batch_year: every user (student or admin) still belongs to one main batch_year
  belongs_to :batch_year

  # Extra batch years for admins (teachers) who may be linked to multiple cohorts/classes
  has_and_belongs_to_many :extra_batch_years,
                          class_name: "BatchYear",
                          join_table: "users_batch_years"
  has_many :library_loan_histories, dependent: :nullify
  before_save :sync_grade_id_from_batch_year

  validates :id_number,
            format: {
              with: /\A\d{6}\z/,
              allow_blank: true,
              message: "需為 6 位數字"
            }

  scope :active, -> { where(resigned_at: nil) }

  def resigned?
    resigned_at.present?
  end

  # Can only restore (cancel resignation) if resigned within the last month (HAK-41)
  def restore_allowed?
    resigned_at.present? && resigned_at >= 1.month.ago
  end

  private

  # Class batches copy batch_year.grade_id; admins/teachers are identified only by `admin` flag now.
  def sync_grade_id_from_batch_year
    return unless batch_year
    self.grade_id = batch_year.grade_id
  end
end
