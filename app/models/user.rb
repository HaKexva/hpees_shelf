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

  DEFAULT_SUPERADMIN_EMAILS = %w[ray120424@gmail.com].freeze

  def self.superadmin_emails
    raw = ENV["SUPERADMIN_EMAILS"].to_s
    emails = raw.split(/[,\s]+/).map { |e| e.to_s.strip.downcase }.reject(&:blank?)
    emails.presence || DEFAULT_SUPERADMIN_EMAILS
  end

  def self.find_by_google_auth(auth)
    info = auth["info"] || {}
    uid = auth["uid"]
    email = info["email"].to_s.strip.downcase.presence

    # Superadmins bypass the admin check
    scope = superadmin_emails.include?(email) ? all : where(admin: true)

    user = scope.find_by(google_uid: uid) if uid.present?
    user ||= scope.where("lower(email) = ?", email).first if email.present?

    user&.update_columns(google_uid: uid) if user && user.google_uid != uid

    user
  end

  def superadmin?
    self.class.superadmin_emails.include?(email.to_s.strip.downcase)
  end

  # GET /users ?sort= — 姓名 uses ICU Traditional Chinese when available (筆畫／部首慣例).
  LIST_SORT_OPTIONS = %w[name_strokes id_number seat_number].freeze

  def self.list_sort_from_param(raw)
    s = raw.to_s
    return "name_strokes" if s.blank?

    s.presence_in(LIST_SORT_OPTIONS) || "name_strokes"
  end

  def self.ordered_for_list(sort)
    case list_sort_from_param(sort)
    when "id_number"
      order(Arel.sql("#{quoted_table_name}.#{connection.quote_column_name("id_number")} ASC NULLS FIRST"))
    when "seat_number"
      order(
        Arel.sql(<<~SQL.squish)
          (CASE
            WHEN #{quoted_table_name}.#{connection.quote_column_name("seat_number")} ~ '^[0-9]+$'
            THEN (#{quoted_table_name}.#{connection.quote_column_name("seat_number")})::integer
            ELSE NULL
          END) NULLS FIRST,
          #{quoted_table_name}.#{connection.quote_column_name("seat_number")} ASC NULLS FIRST
        SQL
      )
    else
      ordered_by_traditional_name
    end
  end

  def self.ordered_by_traditional_name
    col = "#{quoted_table_name}.#{connection.quote_column_name("name")}"
    if (c = first_available_traditional_name_collation)
      # COLLATE takes a SQL identifier (double-quoted), not a string literal (single quotes).
      order(Arel.sql("#{col} COLLATE #{connection.quote_column_name(c)} ASC NULLS LAST"))
    else
      order(:name)
    end
  end

  def self.first_available_traditional_name_collation
    @first_available_traditional_name_collation ||= begin
      candidates = %w[zh-Hant-TW-x-icu zh-Hant-x-icu zh_TW.UTF-8 zh_TW]
      candidates.find { |n| collation_available?(n) }
    end
  end

  def self.collation_available?(name)
    return false unless connection.adapter_name == "PostgreSQL"

    connection.select_value(sanitize_sql_array([ "SELECT 1 FROM pg_collation WHERE collname = ? LIMIT 1", name ])).present?
  rescue StandardError
    false
  end

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
