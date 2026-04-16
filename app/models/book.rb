class Book < ApplicationRecord
  default_scope { where(deleted_at: nil) }

  # Unscoped relation for associations that must resolve soft-deleted books (e.g. circulation history).
  scope :with_deleted, -> { unscope(where: :deleted_at) }
  scope :only_deleted, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }

  belongs_to :batch_year
  # Library single-copy / 捐贈、班級: `user` is current borrower while借閱中.
  # 老師的書: `user` is always the owning teacher; borrowers are only `borrowers` / circulation_records.
  belongs_to :user, -> { merge(User.with_deleted) }, optional: true
  # Soft delete keeps the row; circulation_records remain linked (no dependent: :destroy).
  has_many :circulation_records, inverse_of: :book
  has_many :loan_records, -> { where(returned_at: nil) }, class_name: "CirculationRecord"
  # When total > 1, borrowers are has_many (one circulation_record per copy lent).
  has_many :borrowers, -> { merge(User.with_deleted) }, through: :loan_records, source: :user

  validates :batch_year_id, presence: true
  validates :title, presence: true
  validates :isbn, presence: true
  validates :source, presence: true
  validates :call_number,
            presence: true,
            format: { with: /\A\d{8}\z/, message: "需為 8 位數字" },
            if: :owned_by_library?
  validates :user_id, presence: true, if: :owned_by_teacher?
  validate :isbn_must_be_valid_13_if_present
  validate :teacher_owned_book_batch_year_in_teacher_batches
  enum :source, { owned_by_library: 0, donated: 1, owned_by_class: 2, owned_by_teacher: 3 }
  enum :relocation_behavior, { move_with_class: "move_with_class", stay: "stay" }, default: :move_with_class
  before_validation :normalize_relocation_behavior_for_source
  before_validation :normalize_total

  # 原屆已「畢業」、仍待指定新屆數的書。班級的書且「留班不動」者由學年度切換另行處理，不進此清單（HAK-118）。
  scope :needing_relocation_after_graduated_batch, -> {
    class_key = Book.sources[:owned_by_class]
    joins(:batch_year)
      .where(batch_years: { grade_id: BatchYear::GRADE_GRADUATED, is_office: false })
      .where("NOT (books.source = ? AND books.relocation_behavior = ?)", class_key, "stay")
  }

  # GET /books ?sort= — 書名 uses ICU Traditional Chinese when available (筆畫／部首慣例).
  LIST_SORT_OPTIONS = %w[title_strokes source isbn].freeze

  # Composite `source` param: 班級的書 split by relocation_behavior (list / CSV / inventory).
  LIST_SOURCE_OWNED_BY_CLASS_STAY = "owned_by_class:stay".freeze
  LIST_SOURCE_OWNED_BY_CLASS_MOVE = "owned_by_class:move_with_class".freeze

  def self.list_sort_from_param(raw)
    s = raw.to_s
    return "title_strokes" if s.blank?

    s.presence_in(LIST_SORT_OPTIONS) || "title_strokes"
  end

  def self.ordered_for_list(sort)
    case list_sort_from_param(sort)
    when "source"
      order(:source)
    when "isbn"
      isbn_expr = <<~SQL.squish
        REPLACE(REPLACE(TRIM(COALESCE(#{quoted_table_name}.#{connection.quote_column_name("isbn")}, '')), '-', ''), ' ', '')
      SQL
      order(Arel.sql("#{isbn_expr} ASC NULLS LAST"))
    else
      ordered_by_traditional_title
    end
  end

  def self.ordered_by_traditional_title
    col = "#{quoted_table_name}.#{connection.quote_column_name("title")}"
    if (c = first_available_traditional_title_collation)
      order(Arel.sql("#{col} COLLATE #{connection.quote_column_name(c)} ASC NULLS LAST"))
    else
      order(:title)
    end
  end

  def self.first_available_traditional_title_collation
    @first_available_traditional_title_collation ||= begin
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

  # Current status (stored in Chinese): on-shelf, borrowed, missing, returned-to-library
  STATUS_ON_SHELF = "架上"
  STATUS_BORROWED = "借閱中"
  STATUS_MISSING = "失蹤"
  STATUS_RETURNED_LIBRARY = "歸還圖書館"
  STATUS_OPTIONS = [ [ "架上", STATUS_ON_SHELF ], [ "借閱中", STATUS_BORROWED ], [ "失蹤", STATUS_MISSING ], [ "歸還圖書館", STATUS_RETURNED_LIBRARY ] ].freeze


  # List-page validation: which required fields are still missing
  def missing_required_fields
    msgs = []
    msgs << "書名" if title.blank?
    msgs << "屆數" if batch_year_id.blank?
    msgs << "ISBN" if isbn.blank?
    msgs << "來源" if source.blank?
    msgs
  end

  # Volume part (e.g., upper/lower volumes to distinguish identical ISBNs)
  EDITION_PART_TOP = "上冊"
  EDITION_PART_BOTTOM = "下冊"
  EDITION_PART_OPTIONS = [ [ "—", "" ], [ EDITION_PART_TOP, EDITION_PART_TOP ], [ EDITION_PART_BOTTOM, EDITION_PART_BOTTOM ] ].freeze

  # Display status: borrowed items with borrowed_at more than one day ago are treated as missing (status is stored in Chinese).
  # When borrowed, appends borrower name(s). When total > 1, can show multiple (has many borrowers).
  def display_status
    return status if status == STATUS_RETURNED_LIBRARY
    return STATUS_ON_SHELF if status == STATUS_ON_SHELF
    return STATUS_MISSING if status == STATUS_MISSING
    if status == STATUS_BORROWED && borrowed_at.present? && borrowed_at < 1.day.ago
      STATUS_MISSING
    elsif status == STATUS_BORROWED
      names = borrowers.map(&:name).compact
      if names.empty?
        STATUS_BORROWED
      elsif names.size == 1
        "#{STATUS_BORROWED}（#{names.first}）"
      else
        "#{STATUS_BORROWED}（#{names.join('、')}）"
      end
    else
      STATUS_BORROWED
    end
  end

  def active_circulation_records
    circulation_records.where(returned_at: nil)
  end

  # 未還本數（直接查 DB，避免關聯快取導致「總數 3 借出 1 本後仍可借」算錯）
  def active_loans_count
    CirculationRecord.where(book_id: id, returned_at: nil).count
  end

  def effective_total
    t = total.to_i
    t.positive? ? t : 1
  end

  # 可借冊數（總數 - 未還筆數）。總數 3 借出 1 本後仍為 2，可繼續借。
  def available_copies
    [ effective_total - active_loans_count, 0 ].max
  end

  def can_borrow_copy?
    available_copies.positive?
  end

  # ISBN / 借還：總數大於 1 時只要尚有冊數就可再借（不必仍是「架上」）；單冊則須架上。
  def available_for_checkout?
    return false if status == STATUS_MISSING || status == STATUS_RETURNED_LIBRARY

    effective_total > 1 ? can_borrow_copy? : (status == STATUS_ON_SHELF)
  end

  # Return one active loan for this user (oldest first). When no open loans remain, back to 架上.
  def return_active_loan_for!(user)
    return false if user.blank?

    rec = circulation_records.where(user_id: user.id, returned_at: nil).order(:borrowed_at).first
    return false unless rec

    rec.update!(returned_at: Time.current)
    return true if CirculationRecord.where(book_id: id, returned_at: nil).exists?

    if owned_by_teacher?
      update!(status: STATUS_ON_SHELF, borrowed_at: nil)
    else
      update!(user_id: nil, status: STATUS_ON_SHELF, borrowed_at: nil)
    end
    true
  end

  # Single-copy checkout (not 圖書館多冊分流): records loan; for 老師的書 keeps `user_id` as the teacher.
  def checkout_to_borrower!(borrower)
    circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
    if owned_by_teacher?
      update!(status: STATUS_BORROWED, borrowed_at: Time.current)
    else
      update!(user_id: borrower.id, status: STATUS_BORROWED, borrowed_at: Time.current)
    end
  end

  # Single-copy return (not 圖書館多冊): clears loans; for 老師的書 keeps `user_id` so 來源 label stays the teacher.
  # Clears every open loan at once (e.g. admin 還書). For self-service when multiple copies are lent, use `#return_active_loan_for!`.
  def return_from_single_copy_borrow!
    circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
    if owned_by_teacher?
      update!(status: STATUS_ON_SHELF, borrowed_at: nil)
    else
      update!(user_id: nil, status: STATUS_ON_SHELF, borrowed_at: nil)
    end
  end

  # Return one active loan for this user (oldest first). When no open loans remain, moves the book back to 架上.
  # Used when total > 1 or several borrowers share one title (same as 圖書館多冊 per-user return). Returns false if user has no open loan.
  def return_active_loan_for!(user)
    return false if user.blank?

    rec = circulation_records.where(user_id: user.id, returned_at: nil).order(:borrowed_at).first
    return false unless rec

    rec.update!(returned_at: Time.current)
    if CirculationRecord.where(book_id: id, returned_at: nil).exists?
      return true
    end

    if owned_by_teacher?
      update!(status: STATUS_ON_SHELF, borrowed_at: nil)
    else
      update!(user_id: nil, status: STATUS_ON_SHELF, borrowed_at: nil)
    end
    true
  end

  # After `LibraryLoanHistory` is written: close open loans, mark 歸還圖書館, soft-delete so the row stays for FKs (HAK-75).
  def return_to_library_and_soft_delete!
    raise ArgumentError, "only library holdings support return-to-library" unless owned_by_library?

    circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
    update!(
      user_id: nil,
      status: STATUS_RETURNED_LIBRARY,
      borrowed_at: nil,
      deleted_at: Time.current
    )
  end

  # Soft delete: row remains so circulation_records and FKs stay valid; excluded from default Book scopes.
  def destroy
    return self if deleted_at.present?

    transaction do
      update_columns(deleted_at: Time.current, updated_at: Time.current)
    end
    @destroyed = true
    self
  end

  # True when this user has an active loan (for return eligibility). Supports total > 1 (has many borrowers).
  def borrowed_by?(user)
    return false if user.blank?
    borrowers.exists?(id: user.id)
  end

  # True when book has an ISBN that fails ISBN-13 validation (for showing warnings on list/show)
  def invalid_isbn?
    isbn.present? && !self.class.valid_isbn13?(isbn)
  end

  # Books with at least one loan over one day (借閱超過一天視為失蹤). Single-copy: book.borrowed_at; multi-copy: any active circulation_record.
  scope :overdue_as_missing, -> {
    one_day_ago = 1.day.ago
    where(status: STATUS_BORROWED).where(
      "books.borrowed_at IS NOT NULL AND books.borrowed_at < :cutoff OR EXISTS (SELECT 1 FROM circulation_records cr WHERE cr.book_id = books.id AND cr.returned_at IS NULL AND cr.borrowed_at < :cutoff)",
      cutoff: one_day_ago
    )
  }

  # Normalize ISBN to 13 digits only (strip hyphens/spaces) for comparison. Returns nil if not 13 digits.
  def self.normalize_isbn13(raw)
    s = raw.to_s.gsub(/\D/, "")
    s.length == 13 ? s : nil
  end

  # ISBN-13: 13 digits; check digit = (10 - (weighted sum of first 12 mod 10)) mod 10, weights alternating 1, 3, 1, 3...
  def self.valid_isbn13?(raw)
    digits = raw.to_s.gsub(/\D/, "").chars
    return false unless digits.length == 13

    weights = [ 1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3 ]
    sum = 0
    12.times { |i| sum += digits[i].to_i * weights[i] }
    check = (10 - (sum % 10)) % 10
    check == digits[12].to_i
  end

  # Roo/Excel often yields ISBN as Integer/Float; avoid "978…6.0" from Float#to_s (breaks checksum validation).
  def self.import_isbn_digits(raw)
    return nil if raw.nil?
    return nil if raw.respond_to?(:blank?) && raw.blank?

    digits = case raw
    when Integer then raw.to_s
    when Float, BigDecimal then Integer(raw).to_s
    else raw.to_s.strip.gsub(/\D/, "")
    end
    digits.presence
  rescue ArgumentError, RangeError, TypeError
    raw.to_s.strip.gsub(/\D/, "").presence
  end

  # Map CSV/Excel 來源 cell to `books.source` enum key (same rules as BooksController import).
  def self.import_source_key_from_label(raw)
    return "owned_by_library" if raw.blank?
    s = raw.to_s.strip
    return "owned_by_library" if s.blank?
    return "owned_by_teacher" if s.end_with?("老師的書")
    return "owned_by_library" if s == "圖書館館藏"
    return "donated" if s == "捐贈的書"
    return "owned_by_class" if s == "班級的書"
    return s if sources.key?(s)

    "owned_by_library"
  end

  # "張三老師的書" → "張三"; bare "老師的書" or enum-only labels → nil.
  def self.import_teacher_name_from_owned_by_teacher_label(raw)
    s = raw.to_s.strip
    return nil unless s.end_with?("老師的書")

    s.sub(/老師的書\z/, "").strip.presence
  end

  # Resolves admin user for 老師的書 import rows. nil if missing name or no matching admin (HAK-119).
  def self.import_teacher_user_from_source_label(raw)
    return nil unless import_source_key_from_label(raw) == "owned_by_teacher"

    name = import_teacher_name_from_owned_by_teacher_label(raw)
    return nil if name.blank?

    scope = User.active.where(admin: true)
    scope.find_by(name: name) ||
      scope.find_by(name: "#{name}老師") ||
      scope.where("name LIKE ?", "%#{name}%").first
  end

  # CSV/Excel header → semantic key (shared by import preview + BooksController).
  def self.normalize_import_csv_header(value)
    s = value.to_s.strip
    return nil if s.blank?

    case s
    when "書名" then "title"
    when "總數" then "total"
    when "冊數" then "volume"
    when "備註" then "note"
    when "ISBN", "國際標準書號" then "isbn"
    when "來源" then "source"
    when "登錄號" then "call_number"
    when "屆數" then "batch_year"
    when "屆數ID" then "batch_year_id"
    when "狀態" then "status"
    else s.downcase.presence
    end
  end

  # First matching cell for import preview / BooksController (direct keys, then header-normalized scan).
  def self.lookup_import_row_value(row, *keys)
    return nil if row.blank?

    keys.each do |k|
      v = row[k]
      return v.to_s.strip.presence if v.present? && v.to_s.strip.present?
    end

    targets = keys.map { |k| normalize_import_csv_header(k) || k.to_s.downcase.strip.presence }.compact.uniq
    row.each do |header, val|
      next if val.blank?

      norm = normalize_import_csv_header(header)
      next if norm.blank?
      next unless targets.include?(norm)

      s = val.to_s.strip
      return s if s.present?
    end
    nil
  end

  # Normalized ISBN-13 digits from an import row (same rules as BooksController).
  def self.import_row_isbn_digits(row)
    raw = nil
    %w[isbn ISBN 國際標準書號].each do |k|
      v = row[k]
      next if v.blank?

      raw = v
      break
    end
    if raw.nil?
      row.each do |header, val|
        next if val.blank?
        next unless normalize_import_csv_header(header) == "isbn"

        raw = val
        break
      end
    end
    import_isbn_digits(raw)
  end

  # Compare two ISBNs by normalized 13 digits (so 978-986-181-728-6 matches 9789861817286)
  def self.isbn_match?(stored, input)
    return false if stored.blank?
    n = normalize_isbn13(input)
    n.present? && n == normalize_isbn13(stored)
  end

  private

  def isbn_must_be_valid_13_if_present
    return if isbn.blank?
    return if self.class.valid_isbn13?(isbn)
    errors.add(:isbn, "應為 13 碼且校驗碼正確")
  end

  def teacher_owned_book_batch_year_in_teacher_batches
    return unless owned_by_teacher?
    return if user_id.blank? || batch_year_id.blank?

    owner = User.with_deleted.find_by(id: user_id)
    return if owner.blank?
    return if owner.superadmin?
    return if owner.member_batch_year_ids.include?(batch_year_id)

    errors.add(:batch_year_id, "must be one of the owning teacher's assigned batches")
  end

  def normalize_total
    if owned_by_library?
      # 圖書館館藏一律視為單冊：總數強制為 1
      self.total = 1
    elsif total.blank? || total.to_i <= 0
      # 其他來源：空白或 <= 0 時預設為 1
      self.total = 1
    end
  end

  def normalize_relocation_behavior_for_source
    self.relocation_behavior = "move_with_class" unless owned_by_class?
  end
end
