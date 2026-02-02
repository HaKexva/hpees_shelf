class BatchYear < ApplicationRecord
  # 年級：0 表示「畢業」
  GRADE_GRADUATED = 0

  has_many :books, foreign_key: :batch_year_id, dependent: :nullify
  has_many :users, foreign_key: :batch_year_id, dependent: :nullify

  validates :grade_id, presence: true

  scope :by_number_desc, -> { order(Arel.sql("CASE WHEN batch_number IS NULL THEN 1 ELSE 0 END"), batch_number: :desc) }

  def display_label
    batch_number.present? ? "第 #{batch_number} 屆" : "—"
  end

  def display_label_with_grade
    base = display_label
    return base if base == "—"
    return base if grade_id.nil?
    grade_text = grade_id == GRADE_GRADUATED ? "畢業" : "#{grade_id}年級"
    "#{base}（#{grade_text}）"
  end

  def self.grade_options
    [ [ "（選填）", "" ], [ "畢業", GRADE_GRADUATED ]  ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # 必填用：不含選填
  def self.required_grade_options
    [ [ "畢業", GRADE_GRADUATED ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end
end
