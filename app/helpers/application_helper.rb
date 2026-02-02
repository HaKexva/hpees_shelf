module ApplicationHelper
  # 年級顯示：nil → "—"，0 → "畢業"，其他 → 數字
  def grade_label(grade_id)
    return "—" if grade_id.nil?
    return "畢業" if grade_id == BatchYear::GRADE_GRADUATED
    grade_id.to_s
  end
end
