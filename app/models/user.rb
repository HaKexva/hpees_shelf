class User < ApplicationRecord
  default_scope { where(deleted_at: nil) }

  # Unscoped relation for associations that must resolve soft-deleted users (e.g. circulation history).
  scope :with_deleted, -> { unscope(where: :deleted_at) }
  scope :only_deleted, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }

  # Primary batch_year: every user (student or admin) still belongs to one main batch_year
  belongs_to :batch_year

  # Extra batch years for admins (teachers) who may be linked to multiple cohorts/classes
  has_and_belongs_to_many :extra_batch_years,
                          class_name: "BatchYear",
                          join_table: "users_batch_years"
  has_many :circulation_records
  has_many :loan_records, -> { where(returned_at: nil) }, class_name: "CirculationRecord"
  has_many :borrowed_books, class_name: "Book", through: :loan_records, source: :book

  before_save :sync_grade_id_from_batch_year

  validates :id_number,
            format: {
              with: /\A\d{6}\z/,
              allow_blank: true,
              message: "需為 6 位數字或留空"
            }
  validates :seat_number,
            format: {
              with: /\A\d{1,2}\z/,
              allow_blank: true,
              message: "需為 1~2 位數字或留空"
            }

  scope :active, -> { where(resigned_at: nil) }

  # Soft delete: row remains so circulation_records and FKs stay valid; excluded from default User scopes.
  def destroy
    return self if deleted_at.present?

    transaction do
      update_columns(deleted_at: Time.current, updated_at: Time.current)
    end
    @destroyed = true
    self
  end

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
