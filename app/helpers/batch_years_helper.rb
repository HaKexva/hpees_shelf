module BatchYearsHelper
  MIN_NEW_PERSONNEL_ROWS = 3

  # Relocation 屆數下拉：待送出學年度切換時，選項文字顯示「升學年後」年級預覽（`id` 仍為實際屆數 id）。
  def relocation_batch_year_select_options(collection, staged_commit:)
    Array(collection).map do |batch_year|
      label = if staged_commit
        batch_year.display_label_with_grade_after_school_year_advance
      else
        batch_year.display_label_with_grade
      end
      [ label, batch_year.id ]
    end
  end

  def relocation_batch_year_select_options_by_ids(ids, staged_commit:)
    wanted = Array(ids).reject(&:blank?).map(&:to_i).uniq
    BatchYear.where(id: wanted).order(batch_number: :desc).map do |batch_year|
      label = if staged_commit
        batch_year.display_label_with_grade_after_school_year_advance
      else
        batch_year.display_label_with_grade
      end
      [ label, batch_year.id ]
    end
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
