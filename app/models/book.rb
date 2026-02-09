class Book < ApplicationRecord
  belongs_to :batch_year
  belongs_to :user, optional: true # borrower (for library books)
  validates :batch_year_id, presence: true
  validates :title, presence: true

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
    false
  end

  # The "Return to library" button is only shown during December–February and July–September each year; hidden in other months
  def self.show_return_to_library_button?
    [ 12, 1, 2, 7, 8, 9 ].include?(Date.current.month)
  end

  private

  def set_total_to_one_if_blank
    self.total = 1 if total.blank?
  end
end
