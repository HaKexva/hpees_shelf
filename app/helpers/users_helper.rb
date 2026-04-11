# frozen_string_literal: true

module UsersHelper
  # Maps CSV header to `edit_rows[row_index][...]` key; nil = read-only in preview.
  def user_import_header_semantic_key_for_edit(header)
    h = header.to_s.strip.delete("\uFEFF")
    case h
    when "姓名", "name", "Name" then "name"
    when "學號", "id_number", "Id_number" then "id_number"
    when "座號", "seat_number", "Seat_number" then "seat_number"
    when "屆數ID", "batch_year_id", "Batch_year_id" then "batch_year_id"
    when "電子信箱", "email", "Email" then "email"
    when "管理員", "admin", "Admin" then "admin"
    else
      nil
    end
  end

  def user_import_normalize_header_key(h)
    case h.to_s.strip.delete("\uFEFF")
    when "姓名" then "name"
    when "學號" then "id_number"
    when "座號" then "seat_number"
    when "屆數ID" then "batch_year_id"
    when "電子信箱" then "email"
    when "管理員" then "admin"
    else h.to_s.downcase.presence
    end
  end

  # Resolves a value like UsersController#_user_import_value for one semantic field.
  def user_import_preview_value_for(row, semantic)
    target =
      case semantic.to_s
      when "name" then "name"
      when "id_number" then "id_number"
      when "seat_number" then "seat_number"
      when "batch_year_id" then "batch_year_id"
      when "email" then "email"
      when "admin" then "admin"
      else nil
      end
    return nil if target.blank?

    key_order =
      case semantic.to_s
      when "name" then %w[name Name 姓名]
      when "id_number" then %w[id_number 學號]
      when "seat_number" then %w[seat_number 座號]
      when "batch_year_id" then %w[batch_year_id 屆數ID]
      when "email" then %w[email Email 電子信箱]
      when "admin" then %w[admin 管理員]
      else []
      end

    key_order.each do |k|
      v = row[k] || row[k.to_s]
      s = v.to_s.strip
      return s if s.present?
    end

    row.each do |row_key, v|
      nk = user_import_normalize_header_key(row_key)
      next if nk.blank?
      next unless nk == target

      s = v.to_s.strip
      return s if s.present?
    end
    nil
  end

  # Raw cell for format checks (Float from Excel is preserved; not only string).
  def user_import_preview_raw_for(row, semantic)
    target =
      case semantic.to_s
      when "id_number" then "id_number"
      when "seat_number" then "seat_number"
      when "batch_year_id" then "batch_year_id"
      when "email" then "email"
      when "admin" then "admin"
      else nil
      end
    return nil if target.blank?

    key_order =
      case semantic.to_s
      when "id_number" then %w[id_number 學號]
      when "seat_number" then %w[seat_number 座號]
      when "batch_year_id" then %w[batch_year_id 屆數ID]
      when "email" then %w[email Email 電子信箱]
      when "admin" then %w[admin 管理員]
      else []
      end

    key_order.each do |k|
      v = row[k] || row[k.to_s]
      next if v.nil?
      next if v.respond_to?(:blank?) && v.blank? && !v.is_a?(Numeric) && v != true && v != false

      return v if v.is_a?(Numeric) || v.is_a?(TrueClass) || v.is_a?(FalseClass) || v.to_s.strip.present?
    end

    row.each do |row_key, v|
      nk = user_import_normalize_header_key(row_key)
      next if nk.blank?
      next unless nk == target
      next if v.nil?
      next if v.respond_to?(:blank?) && v.blank? && !v.is_a?(Numeric) && v != true && v != false

      return v if v.is_a?(Numeric) || v.is_a?(TrueClass) || v.is_a?(FalseClass) || v.to_s.strip.present?
    end
    nil
  end

  def user_import_resolved_email_for_preview(row)
    is_admin = User.import_admin_boolean_from_row(row)
    id_number = User.import_cell_student_id_digits(user_import_preview_raw_for(row, "id_number"))
    raw = user_import_preview_raw_for(row, "email")
    unless User.import_user_import_optional_field_blank?(raw)
      return user_import_preview_value_for(row, "email").to_s.strip.presence
    end
    return nil if is_admin
    return "#{id_number}@hpees.tp.edu.tw" if id_number.present?

    nil
  end

  def user_import_row_invalid_tags(row)
    tags = []
    tags << "缺姓名" if user_import_preview_value_for(row, "name").blank?
    is_admin = User.import_admin_boolean_from_row(row)
    unless is_admin
      tags << "學號" unless User.import_student_id_format_ok?(user_import_preview_raw_for(row, "id_number"))
      tags << "座號" unless User.import_seat_format_ok?(user_import_preview_raw_for(row, "seat_number"))
    end
    bid = User.import_batch_year_id_from_row(row)
    tags << "屆數ID" if bid.nil? || bid == -1 || bid < 1
    email = user_import_resolved_email_for_preview(row)
    tags << "電子信箱" if is_admin && email.blank?
    tags << "電子信箱" if email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP)
    tags
  end

  # True when this column fails user import rules (姓名 required; 學號／座號 must match User validations when present; 屆數ID required and valid).
  def user_import_preview_field_invalid?(semantic, row)
    is_admin = User.import_admin_boolean_from_row(row)
    case semantic.to_s
    when "name"
      user_import_preview_value_for(row, "name").blank?
    when "id_number"
      return false if is_admin
      !User.import_student_id_format_ok?(user_import_preview_raw_for(row, "id_number"))
    when "seat_number"
      return false if is_admin
      !User.import_seat_format_ok?(user_import_preview_raw_for(row, "seat_number"))
    when "batch_year_id"
      bid = User.import_batch_year_id_from_row(row)
      bid.nil? || bid == -1 || bid < 1
    when "email"
      email = user_import_resolved_email_for_preview(row)
      (is_admin && email.blank?) || (email.present? && !email.match?(URI::MailTo::EMAIL_REGEXP))
    when "admin"
      false
    else
      false
    end
  end
end
