class BatchYear < ApplicationRecord
  # in_need：0 表示「畢業」
  IN_NEED_GRADUATED = 0

  has_many :books, foreign_key: :batch_year_id, dependent: :nullify
  has_many :users, foreign_key: :batch_year_id, dependent: :nullify

  # 屆數依編號由大至小（14, 13, 12…），無編號排最後
  scope :by_number_desc, -> { order(Arel.sql("CASE WHEN batch_number IS NULL THEN 1 ELSE 0 END"), batch_number: :desc) }

  # 下拉選單顯示用：只顯示「第 X 屆」
  def display_label
    batch_number.present? ? "第 #{batch_number} 屆" : "—"
  end

  # 選擇屆數時顯示：第 X 屆（Y年級）或 第 X 屆（畢業），無 in_need 時僅「第 X 屆」
  def display_label_with_in_need
    base = display_label
    return base if base == "—"
    return base if in_need_id.nil?
    in_need_text = in_need_id == IN_NEED_GRADUATED ? "畢業" : "#{in_need_id}年級"
    "#{base}（#{in_need_text}）"
  end

  # in_need 選項：選填、畢業、1～6（空字串會存成 nil）
  def self.in_need_options
    [ [ "（選填）", "" ], [ "畢業", IN_NEED_GRADUATED ]  ] + (1..6).map { |n| [ n.to_s, n ] }
  end
end
