module ApplicationHelper
  # in_need 顯示：nil → "—"，0 → "畢業"，其他 → 數字
  def in_need_label(in_need_id)
    return "—" if in_need_id.nil?
    return "畢業" if in_need_id == BatchYear::IN_NEED_GRADUATED
    in_need_id.to_s
  end
end
