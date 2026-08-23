module BatchYearsHelper
  MIN_NEW_PERSONNEL_ROWS = 3
  # Placeholder until `advance_to_next_school_year!` creates the new grade-1 batch.
  INCOMING_GRADE1_KEY = "incoming_grade1"

  def incoming_grade1_choice?(choice)
    choice.to_s == INCOMING_GRADE1_KEY
  end

  def incoming_grade1_option_label
    n = (BatchYear.class_batches.maximum(:batch_number) || 0) + 1
    "第 #{n} 屆（1年級）"
  end

  def incoming_grade1_select_option
    [ incoming_grade1_option_label, INCOMING_GRADE1_KEY ]
  end

  def relocation_choice_grade(choice, staged_commit:)
    return 1 if staged_commit && incoming_grade1_choice?(choice)

    by = BatchYear.find_by(id: choice)
    return nil if by.blank?

    staged_commit ? by.grade_id_after_school_year_advance : by.grade_id
  end

  def relocation_choice_grades(raw_ids, staged_commit:)
    Array(raw_ids).reject(&:blank?).filter_map { |raw| relocation_choice_grade(raw, staged_commit: staged_commit) }.uniq
  end

  def resolve_relocation_batch_year_id(raw)
    s = raw.to_s.strip
    return nil if s.blank?
    return incoming_grade1_batch_year_id if incoming_grade1_choice?(s)

    s.to_i
  end

  def incoming_grade1_batch_year_id
    BatchYear.class_batches.where(grade_id: 1).order(batch_number: :desc).pick(:id)
  end

  # Relocation 屆數下拉：待送出學年度切換時，選項文字顯示「升學年後」年級預覽（`id` 仍為實際屆數 id）。
  def relocation_batch_year_select_options(collection, staged_commit:)
    opts = Array(collection).map do |batch_year|
      label = if staged_commit
        batch_year.display_label_with_grade_after_school_year_advance
      else
        batch_year.display_label_with_grade
      end
      [ label, batch_year.id ]
    end
    opts.unshift(incoming_grade1_select_option) if staged_commit
    opts
  end

  def relocation_batch_year_select_options_by_ids(ids, staged_commit:)
    wanted = Array(ids).reject(&:blank?).map(&:to_s)
    include_incoming = staged_commit && wanted.any? { |s| incoming_grade1_choice?(s) }
    numeric_ids = wanted.reject { |s| incoming_grade1_choice?(s) }.map(&:to_i).uniq
    opts = BatchYear.where(id: numeric_ids).order(batch_number: :desc).map do |batch_year|
      label = if staged_commit
        batch_year.display_label_with_grade_after_school_year_advance
      else
        batch_year.display_label_with_grade
      end
      [ label, batch_year.id ]
    end
    opts.unshift(incoming_grade1_select_option) if include_incoming
    opts
  end

  # Trim trailing blank 新進人員 rows (never below min), then pad to min — fixes stale drafts with many empty rows.
  def normalize_new_personnel_rows(rows)
    rows = Array(rows).map do |r|
      h = r.is_a?(Hash) ? r.stringify_keys : {}
      ids = h["batch_year_ids"]
      ids = ids.is_a?(Array) ? ids.reject(&:blank?) : []
      ids = [ h["batch_year_id"] ].compact if ids.blank? && h["batch_year_id"].present?
      { "name" => h["name"], "batch_year_ids" => ids }
    end
    while rows.size > MIN_NEW_PERSONNEL_ROWS && new_personnel_row_blank?(rows.last)
      rows.pop
    end
    rows << {} while rows.size < MIN_NEW_PERSONNEL_ROWS
    rows
  end

  def relocation_new_personnel_rows_for_form(draft)
    draft_np = draft["new_personnel"]
    base =
      if draft_np.is_a?(Array) && draft_np.any?
        draft_np.map do |r|
          h = r.is_a?(Hash) ? r.stringify_keys : {}
          ids = h["batch_year_ids"]
          ids = ids.is_a?(Array) ? ids.reject(&:blank?) : []
          ids = [ h["batch_year_id"] ].compact if ids.blank? && h["batch_year_id"].present?
          { "name" => h["name"], "batch_year_ids" => ids }
        end
      else
        []
      end
    normalize_new_personnel_rows(base)
  end

  private

    def new_personnel_row_blank?(row)
      return true if row.blank?

      h = row.stringify_keys
      ids = h["batch_year_ids"]
      ids = ids.is_a?(Array) ? ids.reject(&:blank?) : []
      ids = [ h["batch_year_id"] ].compact if ids.blank? && h["batch_year_id"].present?
      h["name"].to_s.strip.blank? && ids.blank?
    end
end
