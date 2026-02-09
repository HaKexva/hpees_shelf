class Book < ApplicationRecord
  belongs_to :batch_year
  belongs_to :user, optional: true # borrower (for library books)
  validates :batch_year_id, presence: true
  validates :title, presence: true
  validates :tag, presence: true
  validate :batch_year_not_office
  validate :teacher_tag_must_have_teacher_name

  before_validation :set_total_to_one_if_blank

  # Current status (stored in Chinese): on-shelf, borrowed, missing, returned-to-library
  STATUS_ON_SHELF = "架上"
  STATUS_BORROWED = "借閱中"
  STATUS_MISSING = "失蹤"
  STATUS_RETURNED_LIBRARY = "歸還圖書館"
  STATUS_OPTIONS = [ [ "架上", STATUS_ON_SHELF ], [ "借閱中", STATUS_BORROWED ], [ "失蹤", STATUS_MISSING ], [ "歸還圖書館", STATUS_RETURNED_LIBRARY ] ].freeze

  # Tag (single choice): four types. External: library books, ___ teacher's books, donated books; internal: class books.
  TAG_LIBRARY = "圖書館的書"
  TAG_DONATED = "捐贈的書"
  TAG_CLASS = "班級的書"
  TAG_TEACHER_PREFIX = "老師的書" # When this is selected and a name is given, it is stored as "王老師的書"
  TAG_OPTIONS = [ TAG_LIBRARY, TAG_DONATED, TAG_CLASS, TAG_TEACHER_PREFIX ].freeze
  TAG_FILTER_OPTIONS = [ [ "圖書館的書", TAG_LIBRARY ], [ "捐贈的書", TAG_DONATED ], [ "班級的書", TAG_CLASS ], [ "老師的書", TAG_TEACHER_PREFIX ] ].freeze

  # Chinese names: if two characters, show full name (e.g. "王明老師的書"); if three or more, use the last two characters. English names use the full name (e.g. "Momo老師的書").
  def self.tag_from_teacher_name(name)
    n = name.to_s.strip
    return TAG_TEACHER_PREFIX if n.blank?
    if n.match?(/\p{Han}/)
      if n.length == 2
        "#{n}老師的書"
      else
        last_two = n.length >= 2 ? n[-2..] : n
        last_two.end_with?("老師") ? "#{last_two}的書" : "#{last_two}老師的書"
      end
    else
      "#{n}老師的書"
    end
  end

  def teacher_tag?
    tag.to_s.end_with?("老師的書")
  end

  # List-page validation: which required fields are still missing
  def missing_required_fields
    msgs = []
    msgs << "書名" if title.blank?
    msgs << "屆數" if batch_year_id.blank?
    msgs << "標籤" if tag.blank?
    # For teacher books, if the tag is only "老師的書" without a specific name (e.g. "王老師的書"), treat it as a missing teacher name
    if teacher_tag? && tag == TAG_TEACHER_PREFIX
      msgs << "老師名字"
    end
    msgs
  end

  # Volume part (e.g., upper/lower volumes to distinguish identical ISBNs)
  EDITION_PART_TOP = "上冊"
  EDITION_PART_BOTTOM = "下冊"
  EDITION_PART_OPTIONS = [ [ "—", "" ], [ EDITION_PART_TOP, EDITION_PART_TOP ], [ EDITION_PART_BOTTOM, EDITION_PART_BOTTOM ] ].freeze

  # Display status: borrowed items with borrowed_at more than one day ago are treated as missing (status is stored in Chinese)
  def display_status
    return status if status == STATUS_RETURNED_LIBRARY
    return STATUS_ON_SHELF if status == STATUS_ON_SHELF
    return STATUS_MISSING if status == STATUS_MISSING
    if status == STATUS_BORROWED && borrowed_at.present? && borrowed_at < 1.day.ago
      STATUS_MISSING
    else
      STATUS_BORROWED
    end
  end

  def library_book?
    tag == TAG_LIBRARY
  end

  # The "Return to library" button is only shown during December–February and July–September each year; hidden in other months
  def self.show_return_to_library_button?
    [ 12, 1, 2, 7, 8, 9 ].include?(Date.current.month)
  end

  private

  def teacher_tag_must_have_teacher_name
    return unless tag.to_s == TAG_TEACHER_PREFIX
    errors.add(:tag, :teacher_must_select)
  end

  def set_total_to_one_if_blank
    self.total = 1 if total.blank?
  end

  def batch_year_not_office; end
end
