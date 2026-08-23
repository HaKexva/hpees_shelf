class BatchYear < ApplicationRecord
  # Grade: 0 means "Graduated"
  GRADE_GRADUATED = 0

  has_many :books, foreign_key: :batch_year_id, dependent: :nullify
  # Primary users (students / main assignment)
  has_many :users, foreign_key: :batch_year_id, dependent: :nullify
  # Admins/teachers that are additionally linked to this batch year
  has_and_belongs_to_many :admins,
                          class_name: "User",
                          join_table: "users_batch_years"

  validates :batch_number, presence: true
  validates :grade_id, presence: true

  scope :by_number_desc, -> { order(batch_number: :desc) }
  scope :class_batches, -> { all }
  scope :class_batches_by_number_desc, -> { order(batch_number: :desc) }

  def display_label
    batch_number.present? ? "第 #{batch_number} 屆" : (name.presence || "—")
  end

  def display_label_with_grade
    base = display_label
    return base if base == "—"
    return base if grade_id.nil?
    grade_text = case grade_id
    when GRADE_GRADUATED then "畢業"
    else "#{grade_id}年級"
    end
    "#{base}（#{grade_text}）"
  end

  # Same grade rule as `advance_to_next_school_year!` (UI preview only; DB unchanged).
  def grade_id_after_school_year_advance
    return nil if grade_id.nil?

    (grade_id == YEARS_UNTIL_GRADUATION || grade_id == GRADE_GRADUATED) ? GRADE_GRADUATED : (grade_id + 1)
  end

  def display_label_with_grade_after_school_year_advance
    base = display_label
    return base if base == "—"

    g = grade_id_after_school_year_advance
    return base if g.nil?

    grade_text = case g
    when GRADE_GRADUATED then "畢業"
    else "#{g}年級"
    end
    "#{base}（#{grade_text}）"
  end

  # Import / export round-trip: match CSV「屆數」to a class batch row (exact string == `display_label_with_grade`).
  def self.find_id_from_import_label(label)
    return nil if label.blank?

    s = label.to_s.strip
    return nil if s.blank?

    class_batches.find_each do |by|
      return by.id if by.display_label_with_grade.to_s == s
    end
    nil
  end

  def self.grade_options
    [ [ "（選填）", "" ], [ "畢業", GRADE_GRADUATED ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # For required-field selects: excludes optional blank value
  def self.required_grade_options
    [ [ "畢業", GRADE_GRADUATED ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # Reference: cohort entering in 2025/09 is batch 11 (grade 1). Each year advances one grade; after 6 years they automatically become "Graduated".
  # School year starts in September: current September–next August are the same school year.
  YEARS_UNTIL_GRADUATION = 6
  BASE_BATCH = 11       # ROC school year 114 = batches 1–11
  BASE_SCHOOL_YEAR = 2025
  BASE_SCHOOL_YEAR_ROC = 114 # ROC school year 114 = batches 1–11; each additional school year adds one batch

  # Date-based 學年: month 1–6 => ROC-1, 10–12 => ROC, 7–9 => ambiguous (use stored or run school_year:set when deploying)
  def self.current_school_year_roc
    today = Time.zone.today
    roc = today.year - 1911
    month = today.month
    if (1..6).cover?(month)
      roc - 1
    elsif (10..12).cover?(month)
      roc
    else
      # 7–9: no single date-based value; caller should use display_current_school_year_roc (stored or set via school_year:set)
      roc - 1
    end
  end

  # Displayed current school year in ROC years. Month 7–9 uses stored value only (set via UI "切換學年度" or rake school_year:set when deploying).
  def self.display_current_school_year_roc
    stored = AppSetting.get("current_school_year_roc").presence&.to_i
    return stored if stored.present?
    current_school_year_roc
  end

  # When switching school year, store: current displayed value + 1
  def self.advance_stored_school_year!
    next_roc = display_current_school_year_roc + 1
    AppSetting.set("current_school_year_roc", next_roc)
    next_roc
  end

  # Whether we are allowed to roll back to the previous school year (cannot go earlier than the actual current school year)
  def self.can_rollback_school_year?
    display_current_school_year_roc > current_school_year_roc
  end

  # For testing: roll back to the previous school year (only update stored value); cannot go earlier than the actual current school year
  def self.rollback_stored_school_year!
    current = display_current_school_year_roc
    return current if current <= BASE_SCHOOL_YEAR_ROC
    return current if current <= current_school_year_roc
    prev_roc = current - 1
    AppSetting.set("current_school_year_roc", prev_roc)
    prev_roc
  end

  # For testing: roll back to the previous school year and restore batches (delete the latest batch, decrement all other grades by 1, and decrement stored value by 1); cannot go earlier than the actual current school year
  def self.rollback_school_year!
    return display_current_school_year_roc unless can_rollback_school_year?
    max = class_batches.maximum(:batch_number)
    return rollback_stored_school_year! unless max && max >= 1
    # Delete the class batch with the largest batch_number
    class_batches.where(batch_number: max).destroy_all
    # Among graduated batches, change the one with the largest batch_number back to grade 6; keep all other graduated batches as graduated
    graduated_batch_numbers = class_batches.where(grade_id: GRADE_GRADUATED).pluck(:batch_number).compact
    max_graduated = graduated_batch_numbers.max
    # Decrement grade_id by 1 for all remaining class batches
    class_batches.find_each do |by|
      new_grade = if by.grade_id.blank?
        GRADE_GRADUATED
      elsif by.grade_id == GRADE_GRADUATED && by.batch_number == max_graduated
        6 # The graduated batch with the largest batch_number becomes grade 6 again
      elsif by.grade_id == GRADE_GRADUATED
        GRADE_GRADUATED # Other graduated batches stay graduated
      else
        by.grade_id - 1
      end
      by.update_column(:grade_id, new_grade)
    end
    rollback_stored_school_year!
  end

  # One-click creation of a batch range: calculated from the "current school year" (stored value); when the school year changes this also changes. ROC year 114 = 11 batches; every additional school year adds one batch.
  def self.max_batch_number_for_auto_create
    n = BASE_BATCH + (display_current_school_year_roc - BASE_SCHOOL_YEAR_ROC)
    [ n, 1 ].max
  end

  # Regardless of total number of batches, the 6 batches with the largest batch_number are grades 1–6 (largest = grade 1); all others are graduated. Office batch excluded.
  def self.grade_id_for_batch_number(batch_number)
    return nil if batch_number.blank? || batch_number < 1
    all_numbers = class_batches.distinct.pluck(:batch_number).compact.sort.reverse
    rank = all_numbers.index(batch_number)&.+(1)
    return GRADE_GRADUATED unless rank
    rank.between?(1, YEARS_UNTIL_GRADUATION) ? rank : GRADE_GRADUATED
  end

  # Switch to the next school year: 1) increment all class batch grades by 1 (6 → Graduated) 2) create a new class batch (batch_number = max + 1, grade 1). Office batch excluded.
  def self.advance_to_next_school_year!
    max = class_batches.maximum(:batch_number) || 0
    class_batches.find_each do |by|
      next if by.grade_id.nil?

      new_grade = (by.grade_id == YEARS_UNTIL_GRADUATION || by.grade_id == GRADE_GRADUATED) ? GRADE_GRADUATED : (by.grade_id + 1)
      by.update_column(:grade_id, new_grade)
    end
    create!(batch_number: max + 1, grade_id: 1, name: "第#{max + 1}屆", is_office: false)
  end

  # 班級的書且「留班不動」：每學年改掛「前一屆」屆數，書上 grade_id 不變（HAK-118）。
  def self.shift_stay_class_owned_books_to_previous_batch!
    Book.where(source: :owned_by_class, relocation_behavior: :stay).find_each do |book|
      by = book.batch_year
      next if by.blank? || by.is_office?
      next if by.batch_number.blank? || by.batch_number <= 1

      prev = class_batches.where(is_office: false).find_by(batch_number: by.batch_number - 1)
      next if prev.blank?

      book.update_columns(batch_year_id: prev.id)
    end
  end

  # Whether to show the "Switch to next school year" button: only show in July–September, and only when stored displayed year equals date-based current year (e.g. now 114學年度, in Jul–Sep button shows; after user clicks "切換學年度", stored becomes 115學年度 and button hides).
  def self.show_advance_school_year_button?
    true
  end

  # Reset grade_ids based on batch_number ranking: the 6 largest class batches become grades 1–6, all others become graduated. Office batch excluded.
  def self.reassign_grades_by_rank!
    all_numbers = class_batches.distinct.pluck(:batch_number).compact.sort.reverse
    return if all_numbers.empty?
    all_numbers.each_with_index do |batch_number, index|
      rank = index + 1
      grade_id = rank.between?(1, YEARS_UNTIL_GRADUATION) ? rank : GRADE_GRADUATED
      class_batches.where(batch_number: batch_number).update_all(grade_id: grade_id)
    end
  end

  # Legacy: keep method for callers but do nothing special now that there is no office flag behavior.
  def self.ensure_office_exists!
    # no-op; kept for backwards compatibility
  end
end
