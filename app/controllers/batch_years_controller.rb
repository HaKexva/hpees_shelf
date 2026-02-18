class BatchYearsController < ApplicationController
  before_action :set_batch_year, only: %i[ show edit update destroy ]

  def index
    BatchYear.ensure_office_exists!
    @batch_years = BatchYear.by_number_desc
  end

  def show
    @books = @batch_year.books.where.not(title: [ nil, "" ])
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
    next_roc = BatchYear.advance_stored_school_year!
    # Books in graduated class batches need a new batch assignment
    pending_book_ids = Book.joins(:batch_year).where(batch_years: { grade_id: BatchYear::GRADE_GRADUATED, is_office: false }).pluck(:id)
    pending_user_ids = []

    # Books in non-graduated batches: just sync grade_id
    Book.includes(:batch_year).find_each do |book|
      next if book.batch_year.blank?
      next if pending_book_ids.include?(book.id)
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
    # Teacher's books (老師的書): one choice per teacher; donated / 班級的書: one dropdown per book
    @pending_books_by_teacher = @pending_books.select { |b| b.owned_by_teacher? && b.user_id.present? }.group_by(&:user_id)
    @pending_books_other = @pending_books.reject { |b| b.owned_by_teacher? && b.user_id.present? }
    @pending_users = User.where(id: session[:pending_relocation_user_ids].to_a).includes(:batch_year).to_a
    @batch_years = BatchYear.class_batches_by_number_desc
    @batch_years_with_office = BatchYear.by_number_desc
    @show_return_to_library_button = Book.show_return_to_library_button?
    @any_library_books_to_return = Book.where(source: :owned_by_library).where.not(status: Book::STATUS_RETURNED_LIBRARY).exists?
    if @pending_books.empty? && @pending_users.empty?
      session.delete(:pending_relocation_book_ids)
      session.delete(:pending_relocation_user_ids)
      redirect_to batch_years_path, notice: "無待指定屆數的項目。"
    else
      render :relocation
    end
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

    session.delete(:pending_relocation_book_ids)
    session.delete(:pending_relocation_user_ids)
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
