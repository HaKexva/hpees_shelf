class Book < ApplicationRecord
  belongs_to :batch_year
  validates :batch_year_id, presence: true
  validates :title, presence: true
  validates :tag, presence: true
  validate :batch_year_not_office
  validate :teacher_tag_must_have_teacher_name

  before_validation :set_total_to_one_if_blank

  # 目前狀態（存中文）：架上、借閱中、失蹤、歸還圖書館
  STATUS_ON_SHELF = "架上"
  STATUS_BORROWED = "借閱中"
  STATUS_MISSING = "失蹤"
  STATUS_RETURNED_LIBRARY = "歸還圖書館"
  STATUS_OPTIONS = [ [ "架上", STATUS_ON_SHELF ], [ "借閱中", STATUS_BORROWED ], [ "失蹤", STATUS_MISSING ], [ "歸還圖書館", STATUS_RETURNED_LIBRARY ] ].freeze

  # 標籤（單選）：四種書擇一。外部：圖書館的書、＿＿老師的書、捐贈的書；內部：班級的書。
  TAG_LIBRARY = "圖書館的書"
  TAG_DONATED = "捐贈的書"
  TAG_CLASS = "班級的書"
  TAG_TEACHER_PREFIX = "老師的書" # 選此且填名字時存成 "王老師的書"
  TAG_OPTIONS = [ TAG_LIBRARY, TAG_DONATED, TAG_CLASS, TAG_TEACHER_PREFIX ].freeze

  def self.tag_from_teacher_name(name)
    n = name.to_s.strip
    last_two = n.length >= 2 ? n[-2..] : n
    return TAG_TEACHER_PREFIX if last_two.blank?
    last_two.end_with?("老師") ? "#{last_two}的書" : "#{last_two}老師的書"
  end

  def teacher_tag?
    tag.to_s.end_with?("老師的書")
  end

  # 列表檢查：哪些必填欄位尚未填寫
  def missing_required_fields
    msgs = []
    msgs << "書名" if title.blank?
    msgs << "屆數" if batch_year_id.blank?
    msgs << "標籤" if tag.blank?
    # 老師的書若只有「老師的書」而沒有具名（例如「王老師的書」），視為老師名字遺漏
    if teacher_tag? && tag == TAG_TEACHER_PREFIX
      msgs << "老師名字"
    end
    msgs
  end

  # 上下冊（ISBN 相同時區分）
  EDITION_PART_TOP = "上冊"
  EDITION_PART_BOTTOM = "下冊"
  EDITION_PART_OPTIONS = [ [ "—", "" ], [ EDITION_PART_TOP, EDITION_PART_TOP ], [ EDITION_PART_BOTTOM, EDITION_PART_BOTTOM ] ].freeze

  # 顯示用目前狀態：借閱中且借閱日超過一日視為失蹤（狀態已存中文）
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

  private

  def teacher_tag_must_have_teacher_name
    return unless tag.to_s == TAG_TEACHER_PREFIX
    errors.add(:tag, "老師的書請選擇老師")
  end

  def set_total_to_one_if_blank
    self.total = 1 if total.blank?
  end

  def batch_year_not_office
    return if batch_year_id.blank?
    by = batch_year
    errors.add(:batch_year_id, "書籍不可歸於「老師」屆數（僅人員）") if by&.is_office?
  end
end
