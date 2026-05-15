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

  before_validation :clear_student_id_fields_if_admin
  before_save :sync_grade_id_from_batch_year
  after_save :attach_previous_primary_batch_to_extras_for_admins

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

  # CSV/Excel: "—" / dashes / "無" etc. mean empty for optional 學號、座號 (same as leaving the cell blank).
  IMPORT_BLANK_PLACEHOLDER_STRINGS = %w[
    — – - － ― ‐ -- …
    N/A n/a 無
  ].freeze

  def self.import_blank_placeholder_string?(str)
    s = str.to_s.strip
    s.blank? || IMPORT_BLANK_PLACEHOLDER_STRINGS.include?(s)
  end

  def self.import_user_import_optional_field_blank?(raw)
    return true if raw.nil?
    return false if raw.is_a?(Numeric)
    return true if raw.respond_to?(:blank?) && raw.blank?

    t = raw.to_s.strip.gsub(/\s+/, "")
    import_blank_placeholder_string?(t)
  end

  # CSV/Excel import: Roo may yield Integer/Float; avoid "123456.0" breaking /\A\d{6}\z/.
  def self.import_cell_student_id_digits(raw)
    return "" if import_user_import_optional_field_blank?(raw)

    case raw
    when Integer then raw.to_s
    when Float, BigDecimal then Integer(raw).to_s
    else
      raw.to_s.strip.gsub(/\s+/, "")
    end
  rescue ArgumentError, RangeError, TypeError
    t = raw.to_s.strip.gsub(/\s+/, "")
    import_blank_placeholder_string?(t) ? "" : t
  end

  def self.import_cell_seat_digits(raw)
    import_cell_student_id_digits(raw)
  end

  def self.import_student_id_format_ok?(raw)
    s = import_cell_student_id_digits(raw)
    s.blank? || s.match?(/\A\d{6}\z/)
  end

  def self.import_seat_format_ok?(raw)
    s = import_cell_seat_digits(raw)
    s.blank? || s.match?(/\A\d{1,2}\z/)
  end

  # Optional CSV/Excel「電子信箱」: blank ok; if present must look like an email (unique index applies at save).
  def self.import_email_format_ok?(raw)
    return true if import_user_import_optional_field_blank?(raw)

    s = raw.to_s.strip
    s.match?(URI::MailTo::EMAIL_REGEXP)
  end

  # Optional「屆數ID」: Roo may yield Integer/Float; "3.0" must not break duplicate preview vs DB.
  def self.import_coerce_batch_year_id_cell(raw)
    case raw
    when nil
      nil
    when Integer
      raw.positive? ? raw : nil
    when Float, BigDecimal
      return nil if raw.is_a?(Float) && (raw.nan? || raw.infinite?)

      i = raw.to_i
      return nil unless raw.to_f == i

      i.positive? ? i : nil
    else
      return nil if import_user_import_optional_field_blank?(raw)

      s = raw.to_s.strip
      return nil if s.blank?

      if s.match?(/\A\d+\z/)
        i = s.to_i
        i.positive? ? i : nil
      elsif s.match?(/\A\d+\.\d+\z/)
        f = s.to_f
        i = f.to_i
        (f == i && i.positive?) ? i : nil
      end
    end
  end

  scope :active, -> { where(resigned_at: nil) }

  SUPERADMIN_EMAILS = %w[ray120424@gmail.com tubaxenor@gmail.com].freeze

  # Ray's primary 屆數: 第4屆 (`batch_number` 4) when it exists; otherwise fourth row by `batch_number` ascending.
  def self.default_batch_year_for_superadmin_provision(email)
    return unless email.to_s.downcase.strip == "ray120424@gmail.com"

    BatchYear.find_by(batch_number: 4) || BatchYear.order(:batch_number).offset(3).first
  end

  def self.find_by_google_auth(auth)
    info = auth["info"] || {}
    uid = auth["uid"]
    email = info["email"]
    is_superadmin = SUPERADMIN_EMAILS.include?(email)

    # Superadmins bypass the admin check
    scope = is_superadmin ? all : where(admin: true)

    user = scope.find_by(google_uid: uid) if uid.present?
    user ||= scope.find_by(email: email) if email.present?

    # Auto-provision superadmins who don't have a User record yet
    if user.nil? && is_superadmin
      batch_year =
        default_batch_year_for_superadmin_provision(email) ||
        BatchYear.order(:id).first ||
        BatchYear.create!(batch_number: 1, grade_id: 1, name: "第1屆")
      user = create!(
        name: info["name"] || email.split("@").first,
        email: email,
        google_uid: uid,
        admin: true,
        batch_year: batch_year
      )
    end

    user&.update_columns(google_uid: uid) if user && user.google_uid != uid

    user
  end

  def superadmin?
    SUPERADMIN_EMAILS.include?(email)
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

  # Primary 屆數 plus extra 屆數 links (teachers). Used for borrow rules and teacher-book placement.
  def member_batch_year_ids
    ([ batch_year_id ] + extra_batch_year_ids).compact.uniq
  end

  def may_borrow_from_batch?(batch_year_id)
    return true if superadmin?
    return false if batch_year_id.blank?

    member_batch_year_ids.include?(batch_year_id.to_i)
  end

  private

  def clear_student_id_fields_if_admin
    return unless admin?

    self.id_number = nil
    self.seat_number = nil
  end

  # Class batches copy batch_year.grade_id; admins/teachers are identified only by `admin` flag now.
  def sync_grade_id_from_batch_year
    return unless batch_year
    self.grade_id = batch_year.grade_id
  end

  # When a teacher's primary 屆數 changes (e.g. their class cohort graduated and they take a new class),
  # keep the old 屆數 on `extra_batch_years` instead of only overwriting `batch_year_id`, so borrowing
  # and teacher-book rules (`member_batch_year_ids`) still include the graduated 屆.
  def attach_previous_primary_batch_to_extras_for_admins
    return unless admin?
    return unless saved_change_to_batch_year_id?

    old_id, new_batch_id = saved_change_to_batch_year_id
    return if old_id.blank? || old_id == new_batch_id
    return if extra_batch_year_ids.include?(old_id)

    prev = BatchYear.find_by(id: old_id)
    return if prev.blank?

    extra_batch_years << prev
  end
end
