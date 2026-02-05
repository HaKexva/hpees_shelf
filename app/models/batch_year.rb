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

  def self.grade_options
    [ [ "（選填）", "" ], [ "畢業", GRADE_GRADUATED ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # For required-field selects: excludes optional blank value
  def self.required_grade_options
    [ [ "畢業", GRADE_GRADUATED ] ] + (1..6).map { |n| [ n.to_s, n ] }
  end

  # Reference: cohort entering in 2026/09 is batch 12 (grade 1). Each year advances one grade; after 6 years they automatically become "Graduated".
  # School year starts in September: current September–next August are the same school year.
  YEARS_UNTIL_GRADUATION = 6
  BASE_BATCH = 11       # ROC school year 115 = batches 1–11
  BASE_SCHOOL_YEAR = 2026
  BASE_SCHOOL_YEAR_ROC = 115 # ROC school year 115 = batches 1–11; each additional school year adds one batch

  def self.current_school_year
    today = Time.zone.today
    today.month >= 9 ? today.year + 1 : today.year
  end

  # Current school year in ROC years (Gregorian year - 1911), calculated from the current date
  def self.current_school_year_roc
    current_school_year - 1911
  end

  # Displayed current school year in ROC years (use stored value if present, otherwise calculate from date); updated after switching school year
  def self.display_current_school_year_roc
    stored = AppSetting.get("current_school_year_roc").presence&.to_i
    stored || current_school_year_roc
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

  # One-click creation of a batch range: calculated from the "current school year" (stored value); when the school year changes this also changes. ROC year 115 = 12 batches; every additional school year adds one batch.
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
      new_grade = (by.grade_id == YEARS_UNTIL_GRADUATION || by.grade_id == GRADE_GRADUATED) ? GRADE_GRADUATED : (by.grade_id + 1)
      by.update_column(:grade_id, new_grade)
    end
    create!(batch_number: max + 1, grade_id: 1, name: "第#{max + 1}屆", is_office: false)
  end

  # Whether to show the "Switch to next school year" button: only show from July to September, and only if we have not switched yet (stored value == actual current school year). After switching, hide it.
  def self.show_advance_school_year_button?
    return false unless (7..9).cover?(Date.current.month)
    display_current_school_year_roc == current_school_year_roc
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
