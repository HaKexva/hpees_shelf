module ApplicationHelper
  # On page load, check required fields for the current resource and return an error message string or nil
  def required_fields_alert
    return nil unless controller.is_a?(ActionController::Base)
    msgs = []
    case controller.controller_name
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
