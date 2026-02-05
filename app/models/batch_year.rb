class BatchYear < ApplicationRecord
  # 年級：0 表示「畢業」，7 表示「辦公室老師」（僅人員，無書籍／年級）
  GRADE_GRADUATED = 0
  GRADE_OFFICE = 7  # 辦公室老師（原辦公室）

  has_many :books, foreign_key: :batch_year_id, dependent: :nullify
  has_many :users, foreign_key: :batch_year_id, dependent: :nullify

  before_destroy :prevent_destroy_office

  validates :batch_number, presence: true, unless: :is_office?
  validates :grade_id, presence: true, unless: :is_office?

  scope :class_batches, -> { where(is_office: false) }
  scope :office_only, -> { where(is_office: true) }
  scope :by_number_desc, -> { order(Arel.sql("CASE WHEN is_office THEN 0 WHEN batch_number IS NULL THEN 1 ELSE 0 END"), is_office: :desc, batch_number: :desc) }
  # 書籍存放屆數用：僅班級屆數，不含辦公室
  scope :class_batches_by_number_desc, -> { class_batches.order(batch_number: :desc) }

  def display_label
    return "辦公室老師" if is_office?
    batch_number.present? ? "第 #{batch_number} 屆" : "—"
  end

  def display_label_with_grade
    return "辦公室老師" if is_office?
    base = display_label
    return base if base == "—"
    return base if grade_id.nil?
    grade_text = case grade_id
                 when GRADE_GRADUATED then "畢業"
                 when GRADE_OFFICE then "辦公室老師"
                 else "#{grade_id}年級"
                 end
    "#{base}（#{grade_text}）"
  end

  def self.grade_options
    [ [ "（選填）", "" ], [ "畢業", GRADE_GRADUATED ], [ "辦公室老師", GRADE_OFFICE ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # 必填用：不含選填
  def self.required_grade_options
    [ [ "畢業", GRADE_GRADUATED ], [ "辦公室老師", GRADE_OFFICE ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # 參考：2026/09 第 12 屆入學（1年級）。每年升一級，滿 6 年自動為畢業。
  # 學年度 9 月開始：今年 9 月～明年 8 月為同一學年度。
  YEARS_UNTIL_GRADUATION = 6
  BASE_BATCH = 11       # 115 學年度＝第 1～11 屆
  BASE_SCHOOL_YEAR = 2026
  BASE_SCHOOL_YEAR_ROC = 115 # 115 學年度＝1～11 屆，每多一學年度多一屆

  def self.current_school_year
    today = Time.zone.today
    today.month >= 9 ? today.year + 1 : today.year
  end

  # 目前學年度之中華民國年（西元年 - 1911），依日期計算
  def self.current_school_year_roc
    current_school_year - 1911
  end

  # 顯示用目前學年度（有儲存則用儲存值，否則用日期）；切換學年度後會更新儲存值
  def self.display_current_school_year_roc
    stored = AppSetting.get("current_school_year_roc").presence&.to_i
    stored || current_school_year_roc
  end

  # 切換學年度時寫入：目前顯示值 + 1
  def self.advance_stored_school_year!
    next_roc = display_current_school_year_roc + 1
    AppSetting.set("current_school_year_roc", next_roc)
    next_roc
  end

  # 測試用：返回前一學年度（僅更新儲存值）
  def self.rollback_stored_school_year!
    current = display_current_school_year_roc
    return current if current <= BASE_SCHOOL_YEAR_ROC
    prev_roc = current - 1
    AppSetting.set("current_school_year_roc", prev_roc)
    prev_roc
  end

  # 測試用：返回前一學年度並還原屆數（刪除最新一屆、其餘年級 -1、儲存值 -1）
  def self.rollback_school_year!
    max = class_batches.maximum(:batch_number)
    return rollback_stored_school_year! unless max && max >= 1
    # 刪除編號最大的一屆（班級）
    class_batches.where(batch_number: max).destroy_all
    # 其餘班級屆數年級 -1（畢業維持畢業）
    class_batches.find_each do |by|
      new_grade = (by.grade_id.blank? || by.grade_id == GRADE_GRADUATED) ? GRADE_GRADUATED : (by.grade_id - 1)
      by.update_column(:grade_id, new_grade)
    end
    rollback_stored_school_year!
  end

  # 一鍵建立屆數範圍：依「目前學年度」（儲存值）計算，切換學年度後會一併變動。115 學年度＝12 屆，每多一學年度多一屆。
  def self.max_batch_number_for_auto_create
    n = BASE_BATCH + (display_current_school_year_roc - BASE_SCHOOL_YEAR_ROC)
    [ n, 1 ].max
  end

  # 不論共有幾屆，屆數編號最大的 6 個為 1～6 年級（最大＝一年級），其餘為畢業。不含辦公室。
  def self.grade_id_for_batch_number(batch_number)
    return nil if batch_number.blank? || batch_number < 1
    all_numbers = class_batches.distinct.pluck(:batch_number).compact.sort.reverse
    rank = all_numbers.index(batch_number)&.+(1)
    return GRADE_GRADUATED unless rank
    rank.between?(1, YEARS_UNTIL_GRADUATION) ? rank : GRADE_GRADUATED
  end

  # 切換至下一學年度：1) 班級屆數年級全部 +1（6→畢業）2) 新增一班級屆（編號＝最大+1，一年級）。不含辦公室。
  def self.advance_to_next_school_year!
    max = class_batches.maximum(:batch_number) || 0
    class_batches.find_each do |by|
      new_grade = (by.grade_id == YEARS_UNTIL_GRADUATION || by.grade_id == GRADE_GRADUATED) ? GRADE_GRADUATED : (by.grade_id + 1)
      by.update_column(:grade_id, new_grade)
    end
    create!(batch_number: max + 1, grade_id: 1, name: "第#{max + 1}屆", is_office: false)
  end

  # 是否顯示「切換至下一學年度」按鈕：local 一律顯示；非 local 僅 7～9 月且尚未切換過（儲存值＝日期值）時顯示，切換後自動消失
  def self.show_advance_school_year_button?
    return true if Rails.env.development?
    return false unless (7..9).cover?(Date.current.month)
    display_current_school_year_roc == current_school_year_roc
  end

  # 依屆數編號排名重設年級：班級最大的 6 屆＝1～6 年級，其餘＝畢業。不含辦公室。
  def self.reassign_grades_by_rank!
    all_numbers = class_batches.distinct.pluck(:batch_number).compact.sort.reverse
    return if all_numbers.empty?
    all_numbers.each_with_index do |batch_number, index|
      rank = index + 1
      grade_id = rank.between?(1, YEARS_UNTIL_GRADUATION) ? rank : GRADE_GRADUATED
      class_batches.where(batch_number: batch_number).update_all(grade_id: grade_id)
    end
  end

  # 始終存在一個「辦公室老師」屆數（僅人員，無書籍／年級）。若尚未有 is_office 欄位（migration 未跑）則略過。
  def self.ensure_office_exists!
    return unless column_names.include?("is_office")
    find_or_create_by!(is_office: true) do |b|
      b.batch_number = 0
      b.grade_id = GRADE_OFFICE
      b.name = "辦公室老師"
    end
  end

  private

  def prevent_destroy_office
    throw(:abort) if is_office?
  end
end
