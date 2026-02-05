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
    office_batch = BatchYear.find_by(is_office: true)
    pending_book_ids = []
    pending_user_ids = []

    # Books: class books → keep batch_year, only update grade_id; if the batch is currently grade 6, a new destination must be specified
    Book.includes(:batch_year).find_each do |book|
      next if book.batch_year.blank?
      if book.tag == Book::TAG_CLASS
        if book.batch_year.grade_id == 6
          pending_book_ids << book.id
        else
          book.update_column(:grade_id, book.batch_year.grade_id)
        end
      elsif book.teacher_tag? || book.tag == Book::TAG_DONATED
        pending_book_ids << book.id
      end
      # Library books: unchanged here; users can handle them via the "Return to library" button
    end

    # Users: all admins (teachers) must be assigned a new batch or marked resigned; students (class batches) only update grade_id
    User.includes(:batch_year).find_each do |user|
      if user.admin?
        pending_user_ids << user.id
        next
      end
      next if user.batch_year.blank?
      if user.batch_year.is_office?
        pending_user_ids << user.id
      else
        user.update_column(:grade_id, user.batch_year.grade_id)
      end
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
    # Books from the same teacher are grouped together; assign one batch for the whole group
    teacher_books = @pending_books.select(&:teacher_tag?)
    @pending_books_by_teacher_tag = teacher_books.group_by(&:tag)
    @pending_books_other = @pending_books.reject(&:teacher_tag?)
    @pending_users = User.where(id: session[:pending_relocation_user_ids].to_a).includes(:batch_year).to_a
    @batch_years = BatchYear.class_batches_by_number_desc
    @batch_years_with_office = BatchYear.by_number_desc
    if @pending_books.empty? && @pending_users.empty?
      session.delete(:pending_relocation_book_ids)
      session.delete(:pending_relocation_user_ids)
      redirect_to batch_years_path, notice: "無待指定屆數的項目。"
    else
      render :relocation
    end
  end

  def apply_relocation
    BatchYear.ensure_office_exists!
    pending_book_ids = session[:pending_relocation_book_ids].to_a
    office_batch = BatchYear.find_by(is_office: true)

    # Books from the same teacher: assign batch by tag in one operation
    by_teacher = params[:book_assignments_by_teacher].to_unsafe_h
    by_teacher.each do |tag, batch_year_id|
      next if batch_year_id.blank?
      batch_year = BatchYear.find_by(id: batch_year_id)
      next if batch_year.blank? || batch_year.is_office?
      Book.where(id: pending_book_ids, tag: tag).find_each do |book|
        book.update(batch_year_id: batch_year.id, grade_id: batch_year.grade_id)
      end
    end

    # Other books (donated, grade-6 class books, etc.): assign batch one by one
    book_assignments = params[:book_assignments].to_unsafe_h
    book_assignments.each do |book_id, batch_year_id|
      next if batch_year_id.blank?
      book = Book.find_by(id: book_id)
      batch_year = BatchYear.find_by(id: batch_year_id)
      next if book.blank? || batch_year.blank? || batch_year.is_office?
      book.update(batch_year_id: batch_year.id, grade_id: batch_year.grade_id)
    end

    # Users: can be assigned to a batch or marked as "resigned"
    user_assignments = params[:user_assignments].to_unsafe_h
    user_assignments.each do |user_id, value|
      next if value.blank?
      user = User.find_by(id: user_id)
      next if user.blank?
      if value == "resigned"
        user.update!(resigned_at: Time.current, batch_year_id: office_batch&.id, grade_id: nil)
      else
        batch_year = BatchYear.find_by(id: value)
        next if batch_year.blank?
        user.update(batch_year_id: batch_year.id, grade_id: batch_year.is_office? ? nil : batch_year.grade_id, resigned_at: nil)
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
      count = BatchYear.where(id: ids).where(is_office: false).destroy_all.size
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
      params.expect(batch_year: [ :grade_id, :batch_number, :is_office, :name ])
    end
end
