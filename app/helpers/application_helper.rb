module ApplicationHelper
  # On page load, check required fields for the current resource and return an error message string or nil
  def required_fields_alert
    return nil unless controller.is_a?(ActionController::Base)
    msgs = []
    case controller.controller_name
    when "books"
      book = controller.instance_variable_get(:@book)
      if book.present? && %w[show edit].include?(controller.action_name)
        msgs << "書名為必填" if book.title.blank?
        msgs << "屆數為必填" if book.batch_year_id.blank?
        msgs << "標籤為必填" if book.tag.blank?
        if book.teacher_tag? && book.tag == Book::TAG_TEACHER_PREFIX
          msgs << "老師名字建議填寫（目前僅為「老師的書」）"
        end
      end
    when "users"
      user = controller.instance_variable_get(:@user)
      if user.present? && %w[show edit].include?(controller.action_name)
        msgs << "姓名為必填" if user.name.blank?
        msgs << "屆數為必填" if user.batch_year_id.blank?
      end
    when "batch_years"
      batch_year = controller.instance_variable_get(:@batch_year)
      if batch_year.present? && %w[show edit].include?(controller.action_name)
        msgs << "屆數（編號）為必填" if batch_year.batch_number.blank?
        msgs << "年級為必填" if batch_year.grade_id.blank?
      end
    end
    msgs.any? ? msgs.join("；") : nil
  end

  # Grade display: nil → "—", 0 → "Graduated", 7 → "Office teacher", 1–6 → the grade number
  def grade_label(grade_id)
    return "—" if grade_id.nil?
    return "畢業" if grade_id == BatchYear::GRADE_GRADUATED
    grade_id.to_s
  end
end
