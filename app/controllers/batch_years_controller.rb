class BatchYearsController < ApplicationController
  before_action :set_batch_year, only: %i[ show edit update destroy ]

  def index
    BatchYear.ensure_office_exists!
    @batch_years = BatchYear.by_number_desc
  end

  def show
    @books = @batch_year.books.where.not(title: [ nil, "" ]).includes(:batch_year).order(:title)
    @users = @batch_year.users.order(:admin, :name)
  end

  def new
    @batch_year = BatchYear.new
  end

  def edit
  end

  def create
    @batch_year = BatchYear.new(batch_year_params)
    if @batch_year.save
      redirect_to @batch_year, notice: "屆數已建立。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @batch_year.update(batch_year_params)
      redirect_to @batch_year, notice: "屆數已更新。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @batch_year.destroy!
    redirect_to batch_years_path, notice: "屆數已刪除。", status: :see_other
  end

  def auto_create
    BatchYear.ensure_office_exists!
    max = BatchYear.max_batch_number_for_auto_create
    1.upto(max) do |n|
      by = BatchYear.find_or_initialize_by(batch_number: n)
      by.grade_id = BatchYear::GRADE_GRADUATED if by.grade_id.blank?
      by.name = "第#{n}屆" if by.name.blank?
      by.save!
    end
    BatchYear.reassign_grades_by_rank!
    redirect_to batch_years_path, notice: "已建立／更新第1屆～第 #{max} 屆。", status: :see_other
  end

  def reassign_grades
    BatchYear.advance_to_next_school_year!
    BatchYear.shift_stay_class_owned_books_to_previous_batch!
    next_roc = BatchYear.advance_stored_school_year!
    # Books in graduated class batches need a new batch assignment（「留班不動」班級書除外；已改掛前一屆）
    pending_book_ids = Book.needing_relocation_after_graduated_batch.pluck(:id)
    pending_user_ids = []

    # Books in non-graduated batches: just sync grade_id
    Book.includes(:batch_year).find_each do |book|
      next if book.batch_year.blank?
      next if pending_book_ids.include?(book.id)
      next if book.owned_by_class? && book.stay?
      book.update_column(:grade_id, book.batch_year.grade_id)
    end

    # Users: all admins (teachers) must be assigned a new batch or marked resigned; students only update grade_id
    User.includes(:batch_year).find_each do |user|
      if user.admin?
        pending_user_ids << user.id
        next
      end
      next if user.batch_year.blank?
      user.update_column(:grade_id, user.batch_year.grade_id)
    end

    if pending_book_ids.any? || pending_user_ids.any?
      session[:pending_relocation_book_ids] = pending_book_ids
      session[:pending_relocation_user_ids] = pending_user_ids
      redirect_to relocation_batch_years_path, notice: "已切換至#{next_roc}學年度。請為下列書籍與人員指定新屆數。", status: :see_other
    else
      redirect_to batch_years_path, notice: "已切換至#{next_roc}學年度。", status: :see_other
    end
  end

  def relocation
    pending_book_ids = session[:pending_relocation_book_ids].to_a
    @pending_books = Book.where(id: pending_book_ids).includes(:batch_year).to_a
    @pending_books_by_teacher = @pending_books.select { |b| b.owned_by_teacher? && b.user_id.present? }.group_by(&:user_id)
    @pending_books_other = @pending_books.reject { |b| b.owned_by_teacher? && b.user_id.present? }
    @pending_users = User.where(id: session[:pending_relocation_user_ids].to_a).includes(:batch_year).to_a
    @batch_years = BatchYear.class_batches_by_number_desc
    @batch_years_with_office = BatchYear.by_number_desc
    @show_return_to_library_button = Book.show_return_to_library_button?
    @any_library_books_to_return = Book.where(source: :owned_by_library).where.not(status: Book::STATUS_RETURNED_LIBRARY).exists?
    @relocation_draft = session[:relocation_draft] || {}
    @resigned_restorable = User.where.not(resigned_at: nil).where("resigned_at >= ?", 1.month.ago).includes(:batch_year).order(:name)
    if @pending_books.empty? && @pending_users.empty? && @resigned_restorable.empty?
      session.delete(:pending_relocation_book_ids)
      session.delete(:pending_relocation_user_ids)
      session.delete(:relocation_draft)
      redirect_to batch_years_path, notice: "無待指定屆數的項目。"
    else
      render :relocation
    end
  end

  def save_relocation_draft
    new_personnel = Array(params[:new_personnel]).map do |p|
      p = p.to_unsafe_h if p.respond_to?(:to_unsafe_h)
      p.is_a?(Hash) ? p.slice("name", "id_number", "batch_year_id") : {}
    end
    draft = {
      "teacher_book_assignments" => (params[:teacher_book_assignments] || {}).to_unsafe_h,
      "book_assignments" => (params[:book_assignments] || {}).to_unsafe_h,
      "user_assignments" => (params[:user_assignments] || {}).to_unsafe_h,
      "resigned_assignments" => (params[:resigned_assignments] || {}).to_unsafe_h,
      "new_personnel" => new_personnel
    }
    session[:relocation_draft] = draft
    redirect_to relocation_batch_years_path, notice: "草稿已儲存。", status: :see_other
  end

  def apply_relocation
    pending_book_ids = session[:pending_relocation_book_ids].to_a
    # Teacher's books: one batch per teacher (from teacher_assignments[user_id])
    teacher_assignments = params[:teacher_book_assignments].to_unsafe_h
    teacher_assignments.each do |user_id, batch_year_id|
      next if batch_year_id.blank?
      batch_year = BatchYear.find_by(id: batch_year_id)
      next if batch_year.blank?
      Book.where(user_id: user_id, source: :owned_by_teacher).where(id: pending_book_ids).update_all(batch_year_id: batch_year.id, grade_id: batch_year.grade_id)
    end
    # Other books (捐贈的書, 班級的書, etc.): assign batch one by one
    book_assignments = params[:book_assignments].to_unsafe_h
    book_assignments.each do |book_id, batch_year_id|
      next if batch_year_id.blank?
      book = Book.find_by(id: book_id)
      batch_year = BatchYear.find_by(id: batch_year_id)
      next if book.blank? || batch_year.blank?
      book.update(batch_year_id: batch_year.id, grade_id: batch_year.grade_id)
    end

    # Users: can be assigned to a batch or marked as "resigned"
    user_assignments = params[:user_assignments].to_unsafe_h
    user_assignments.each do |user_id, value|
      next if value.blank?
      user = User.find_by(id: user_id)
      next if user.blank?
      if value == "resigned"
        user.update!(resigned_at: Time.current, grade_id: nil)
      else
        batch_year = BatchYear.find_by(id: value)
        next if batch_year.blank?
        user.update(batch_year_id: batch_year.id, grade_id: batch_year.grade_id, resigned_at: nil)
      end
    end

    # Resigned users (restorable within 1 month): assign batch to restore (HAK-41)
    resigned_assignments = params[:resigned_assignments].to_unsafe_h
    resigned_assignments.each do |user_id, batch_year_id|
      next if batch_year_id.blank?
      user = User.find_by(id: user_id)
      next if user.blank? || !user.restore_allowed?
      batch_year = BatchYear.find_by(id: batch_year_id)
      next if batch_year.blank?
      user.update!(batch_year_id: batch_year.id, grade_id: batch_year.grade_id, resigned_at: nil)
    end

    # New personnel (HAK-41); id_number must be 6 digits if present
    Array(params[:new_personnel]).each do |p|
      name = p[:name].to_s.strip
      next if name.blank?
      raw_id = p[:id_number].to_s.strip
      id_number = raw_id.match?(/\A\d{6}\z/) ? raw_id : nil
      batch_year_id = p[:batch_year_id].to_s.strip.presence
      next if batch_year_id.blank?
      by = BatchYear.find_by(id: batch_year_id)
      next if by.blank?
      User.create!(name: name, id_number: id_number, batch_year_id: by.id, grade_id: by.grade_id, admin: false)
    end

    session.delete(:pending_relocation_book_ids)
    session.delete(:pending_relocation_user_ids)
    session.delete(:relocation_draft)
    redirect_to batch_years_path, notice: "已儲存屆數指定。", status: :see_other
  end

  # For testing: roll back to the previous school year and restore batches as well; cannot go earlier than the actual current school year
  def rollback_school_year
    before_roc = BatchYear.display_current_school_year_roc
    prev_roc = BatchYear.rollback_school_year!
    if prev_roc == before_roc
      redirect_to batch_years_path, alert: "不可返回超過目前實際學年度（#{BatchYear.current_school_year_roc}學年度）。", status: :see_other
    else
      redirect_to batch_years_path, notice: "已返回#{prev_roc}學年度（測試用）。", status: :see_other
    end
  end

  def bulk_destroy
    ids = Array(params[:batch_year_ids]).reject(&:blank?).map(&:to_i)
    if ids.any?
      count = BatchYear.where(id: ids).destroy_all.size
      redirect_to batch_years_path, notice: "已刪除 #{count} 個屆數。", status: :see_other
    else
      redirect_to batch_years_path, alert: "請至少選擇一個屆數。", status: :see_other
    end
  end

  private
    def set_batch_year
      @batch_year = BatchYear.find(params.expect(:id))
    end

    def batch_year_params
      params.expect(batch_year: [ :grade_id, :batch_number, :name ])
    end
end
