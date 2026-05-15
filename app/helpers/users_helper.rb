# frozen_string_literal: true

module UsersHelper
  # Maps CSV header to `edit_rows[row_index][...]` key; nil = read-only in preview.
  def user_import_header_semantic_key_for_edit(header)
    h = header.to_s.strip.delete("\uFEFF")
    case h
    when "姓名", "name", "Name" then "name"
    when "學號", "id_number", "Id_number" then "id_number"
    when "座號", "seat_number", "Seat_number" then "seat_number"
    when "屆數ID", "batch_year_id" then "batch_year_id"
    when "屆數", "batch_year" then "batch_year"
    when "電子信箱", "email", "Email" then "email"
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
    when "屆數" then "batch_year"
    when "電子信箱" then "email"
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
      when "batch_year" then "batch_year"
      when "email" then "email"
      else nil
      end
    return nil if target.blank?

    key_order =
      case semantic.to_s
      when "name" then %w[name Name 姓名]
      when "id_number" then %w[id_number 學號]
      when "seat_number" then %w[seat_number 座號]
      when "batch_year_id" then %w[batch_year_id 屆數ID]
      when "batch_year" then %w[batch_year 屆數]
      when "email" then %w[email 電子信箱 Email]
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
      else nil
      end
    return nil if target.blank?

    key_order =
      case semantic.to_s
      when "id_number" then %w[id_number 學號]
      when "seat_number" then %w[seat_number 座號]
      when "batch_year_id" then %w[batch_year_id 屆數ID]
      when "email" then %w[email 電子信箱 Email]
      else []
      end

    key_order.each do |k|
      v = row[k] || row[k.to_s]
      next if v.nil?
      next if v.respond_to?(:blank?) && v.blank? && !v.is_a?(Numeric)

      return v if v.is_a?(Numeric) || v.to_s.strip.present?
    end

    row.each do |row_key, v|
      nk = user_import_normalize_header_key(row_key)
      next if nk.blank?
      next unless nk == target
      next if v.nil?
      next if v.respond_to?(:blank?) && v.blank? && !v.is_a?(Numeric)

      return v if v.is_a?(Numeric) || v.to_s.strip.present?
    end
    nil
  end

  def user_import_row_invalid_tags(row)
    tags = []
    tags << "缺姓名" if user_import_preview_value_for(row, "name").blank?
    tags << "學號" unless User.import_student_id_format_ok?(user_import_preview_raw_for(row, "id_number"))
    tags << "座號" unless User.import_seat_format_ok?(user_import_preview_raw_for(row, "seat_number"))
    tags << "電子信箱" unless User.import_email_format_ok?(user_import_preview_raw_for(row, "email"))

    id_raw = user_import_preview_raw_for(row, "batch_year_id")
    parsed = User.import_coerce_batch_year_id_cell(id_raw)
    cell_present = id_raw.is_a?(Numeric) || (id_raw.respond_to?(:to_s) && id_raw.to_s.strip.present?)
    if cell_present
      tags << "屆數ID" unless parsed.present? && BatchYear.exists?(id: parsed)
    else
      lab = user_import_preview_value_for(row, "batch_year")
      tags << "屆數" if lab.present? && BatchYear.find_id_from_import_label(lab).blank?
    end

    tags
  end

  # True when this column fails user import rules (姓名 required; 學號／座號 must match User validations when present).
  def user_import_preview_field_invalid?(semantic, row)
    case semantic.to_s
    when "name"
      user_import_preview_value_for(row, "name").blank?
    when "id_number"
      !User.import_student_id_format_ok?(user_import_preview_raw_for(row, "id_number"))
    when "seat_number"
      !User.import_seat_format_ok?(user_import_preview_raw_for(row, "seat_number"))
    when "email"
      !User.import_email_format_ok?(user_import_preview_raw_for(row, "email"))
    when "batch_year_id"
      raw = user_import_preview_raw_for(row, "batch_year_id")
      parsed = User.import_coerce_batch_year_id_cell(raw)
      cell_present = raw.is_a?(Numeric) || (raw.respond_to?(:to_s) && raw.to_s.strip.present?)
      cell_present && !(parsed.present? && BatchYear.exists?(id: parsed))
    when "batch_year"
      lab = user_import_preview_value_for(row, "batch_year")
      lab.present? && BatchYear.find_id_from_import_label(lab).blank?
    else
      false
    end
  end

  # Matches UsersController#_user_import_batch_year_id_for_row for preview badges (新增 vs 待選屆數).
  def user_import_row_effective_batch_year_id(row, fallback_id)
    id_raw = user_import_preview_raw_for(row, "batch_year_id")
    unless id_raw.nil?
      parsed = User.import_coerce_batch_year_id_cell(id_raw)
      cell_present = id_raw.is_a?(Numeric) || (id_raw.respond_to?(:to_s) && id_raw.to_s.strip.present?)
      return parsed if parsed.present? && BatchYear.exists?(id: parsed)

      return nil if cell_present
    end

    lab = user_import_preview_value_for(row, "batch_year")
    if lab.present?
      bid = BatchYear.find_id_from_import_label(lab)
      return bid if bid.present?

      return nil
    end

    fb = fallback_id.to_i
    fb.positive? ? fb : nil
  end
end
