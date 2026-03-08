class Book < ApplicationRecord
  belongs_to :batch_year
  belongs_to :user, optional: true # current borrower (single-copy) or teacher (owned_by_teacher)
  has_many :circulation_records
  has_many :loan_records, -> { where(returned_at: nil) }, class_name: "CirculationRecord"
  # When total > 1, borrowers are has_many (one circulation_record per copy lent).
  has_many :borrowers, through: :loan_records, source: :user

  validates :batch_year_id, presence: true
  validates :title, presence: true
  validates :isbn, presence: true
  validates :source, presence: true
  validates :call_number,
            presence: true,
            format: { with: /\A\d{8}\z/, message: "需為 8 位數字" },
            if: :owned_by_library?
  validate :isbn_must_be_valid_13_if_present
  enum :source, { owned_by_library: 0, donated: 1, owned_by_class: 2, owned_by_teacher: 3 }
  before_validation :set_total_to_one_if_blank

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

  # The "Return to library" button is only shown during 7–9 (Jul–Sep) and 12–2 (Dec–Feb); hidden in other months
  def self.show_return_to_library_button?
    [ 1, 2, 7, 8, 9, 12 ].include?(Date.current.month)
  end

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

  def set_total_to_one_if_blank
    self.total = 1 if total.blank? || total.to_i <= 0
  end
end
