class BatchYear < ApplicationRecord
  # 年級：0 表示「畢業」
  GRADE_GRADUATED = 0

  has_many :books, foreign_key: :batch_year_id, dependent: :nullify
  has_many :users, foreign_key: :batch_year_id, dependent: :nullify

  validates :batch_number, presence: true
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

  # 參考：2026/09 第 12 屆入學（1年級）。每年升一級，滿 6 年自動為畢業。
  # 學年度 9 月開始：今年 9 月～明年 8 月為同一學年度。
  YEARS_UNTIL_GRADUATION = 6
  BASE_BATCH = 12
  BASE_SCHOOL_YEAR = 2026

  def self.current_school_year
    today = Time.zone.today
    today.month >= 9 ? today.year + 1 : today.year
  end

  # 目前學年度之中華民國年（西元年 - 1911），供顯示用
  def self.current_school_year_roc
    current_school_year - 1911
  end

  # 一鍵建立屆數範圍：9 月（含）起為第 1～12 屆，8 月（含）以前為第 1～11 屆
  def self.max_batch_number_for_auto_create
    Date.current.month >= 9 ? 12 : 11
  end

  # 不論共有幾屆，屆數編號最大的 6 個為 1～6 年級（最大＝一年級），其餘為畢業。例：共 11 屆則 6～11 屆＝六～一年級。
  def self.grade_id_for_batch_number(batch_number)
    return nil if batch_number.blank? || batch_number < 1
    all_numbers = distinct.pluck(:batch_number).compact.sort.reverse
    rank = all_numbers.index(batch_number)&.+(1)
    return GRADE_GRADUATED unless rank
    rank.between?(1, YEARS_UNTIL_GRADUATION) ? rank : GRADE_GRADUATED
  end

  # 依屆數編號排名重設年級：最大的 6 屆＝1～6 年級，其餘＝畢業。
  # 僅更新屆數（BatchYear）的 grade_id，不修改人、書；人、書的年級以所屬屆數為準。
  def self.reassign_grades_by_rank!
    all_numbers = distinct.pluck(:batch_number).compact.sort.reverse
    return if all_numbers.empty?
    all_numbers.each_with_index do |batch_number, index|
      rank = index + 1
      grade_id = rank.between?(1, YEARS_UNTIL_GRADUATION) ? rank : GRADE_GRADUATED
      where(batch_number: batch_number).update_all(grade_id: grade_id)
    end
  end
end
