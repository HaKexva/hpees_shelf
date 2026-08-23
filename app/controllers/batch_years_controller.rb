class BatchYearsController < ApplicationController
  include BatchYearsHelper

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
    pending_book_ids, pending_user_ids = dry_run_relocation_pending_ids
    if pending_book_ids.any? || pending_user_ids.any?
      replace_relocation_state!(
        "pending_book_ids" => pending_book_ids,
        "pending_user_ids" => pending_user_ids,
        "pending_commit" => true,
        "draft" => {},
        "draft_saved" => false
      )
      redirect_to relocation_batch_years_path,
                  notice: "請填寫並提交「儲存屆數指定」以完成下學年度切換（儲存草稿不會更新學年度）。",
                  status: :see_other
    else
      _pb, _pu, next_roc = advance_school_year_and_sync!
      redirect_to batch_years_path, notice: "已切換至#{next_roc}學年度。", status: :see_other
    end
  end

  def relocation
    drop_relocation_session_payload!
    state = relocation_state
    @relocation_school_year_pending_commit = state["pending_commit"].present?
    pending_book_ids = Array(state["pending_book_ids"])
    @pending_books = Book.where(id: pending_book_ids).includes(:batch_year).to_a
    @pending_users = User.where(id: Array(state["pending_user_ids"])).includes(:batch_year).to_a
    @batch_years = BatchYear.class_batches_by_number_desc
    @batch_years_with_office = BatchYear.by_number_desc
    @any_library_books_to_return = Book.where(source: :owned_by_library).where.not(status: Book::STATUS_RETURNED_LIBRARY).exists?
    @relocation_draft = state["draft"].presence || {}
    @relocation_draft_saved = state["draft_saved"].present?
    @relocation_batch_year_grade_map =
      BatchYear.by_number_desc.each_with_object({}) do |by, h|
        g = @relocation_school_year_pending_commit ? by.grade_id_after_school_year_advance : by.grade_id
        h[by.id.to_s] = g
      end
    @relocation_batch_year_grade_map[INCOMING_GRADE1_KEY] = 1 if @relocation_school_year_pending_commit
    @resigned_restorable = User.where.not(resigned_at: nil).where("resigned_at >= ?", 1.month.ago).includes(:batch_year).order(:name)

    teacher_books = @pending_books.select { |b| b.owned_by_teacher? && b.user_id.present? }
    grouped = teacher_books.group_by(&:user_id)
    @pending_teacher_books_multi = {}
    @pending_teacher_books_single = {}
    grouped.each do |uid, books|
      teacher = books.first&.user
      linked_ids = teacher&.member_batch_year_ids.to_a
      if linked_ids.size >= 2
        @pending_teacher_books_multi[uid] = books
      else
        @pending_teacher_books_single[uid] = books
      end
    end

    @pending_books_donated = @pending_books.select(&:donated?)
    @pending_books_class = @pending_books.select(&:owned_by_class?)
    @pending_books_library = @pending_books.select(&:owned_by_library?)
    @donated_books_optional =
      Book.where(source: :donated)
          .where.not(status: Book::STATUS_RETURNED_LIBRARY)
          .where.not(id: @pending_books_donated.map(&:id))
          .includes(:batch_year)
          .order(:title)
    if @pending_books.empty? && @pending_users.empty? && @resigned_restorable.empty?
      clear_relocation_state!
      redirect_to batch_years_path, notice: "無待指定屆數的項目。"
    else
      render :relocation
    end
  end

  def apply_relocation
    if params[:commit].to_s == "儲存草稿"
      persist_relocation_draft!
      write_relocation_state!("draft_saved" => true)
      redirect_to relocation_batch_years_path, notice: "草稿已儲存。", status: :see_other
      return
    end

    unless relocation_state["draft_saved"].present?
      redirect_to relocation_batch_years_path, alert: "請先儲存草稿，確認書籍與老師勾選後才可移動。", status: :see_other
      return
    end

    grade_teacher_ids = relocation_param_hash(:grade_teacher_ids)
    required_grades = (1..6).map(&:to_s)
    missing = required_grades.reject { |g| grade_teacher_ids[g].to_s.strip.present? }
    if missing.any?
      redirect_to relocation_batch_years_path, alert: "請為每個年級勾選 1 位老師後才可移動。", status: :see_other
      return
    end

    staged_commit = relocation_state["pending_commit"].present?

    unless current_user&.superadmin?
      picked_ids = required_grades.map { |g| grade_teacher_ids[g].to_s.strip }.uniq
      if picked_ids.size != 1 || picked_ids.first != current_user.id.to_s
        redirect_to relocation_batch_years_path, alert: "您只能勾選自己為年級負責老師。", status: :see_other
        return
      end
    end

    teacher_batch_h = relocation_param_hash(:teacher_batch_year_ids)
    required_grades.each do |g|
      tid = grade_teacher_ids[g].to_s.strip
      raw_ids = teacher_batch_h[tid].presence || teacher_batch_h[tid.to_i] || []
      grades = relocation_choice_grades(raw_ids, staged_commit: staged_commit)
      unless grades.include?(g.to_i)
        redirect_to relocation_batch_years_path, alert: "年級負責老師必須有任教該年級（請先在下方為該老師勾選任教屆數，再重新儲存草稿）。", status: :see_other
        return
      end
    end
    pending_book_ids = Array(relocation_state["pending_book_ids"])
    if (msg = relocation_book_assignments_error_message(pending_book_ids))
      redirect_to relocation_batch_years_path, alert: msg, status: :see_other
      return
    end

    ActiveRecord::Base.transaction do
      if staged_commit
        pending_book_ids, = advance_school_year_and_sync!
      end

      # Per-book assignments (multi-cohort teacher books + donated/class books)
      book_assignments = relocation_param_hash(:book_assignments)
      book_assignments.each do |book_id, batch_year_id|
        next if batch_year_id.blank?
        book = Book.find_by(id: book_id)
        batch_year = BatchYear.find_by(id: resolve_relocation_batch_year_id(batch_year_id))
        next if book.blank? || batch_year.blank?
        book.update!(batch_year_id: batch_year.id, grade_id: batch_year.grade_id)
      end

      # Teachers: primary batch + extra batches (multi-select), or resigned
      teacher_batch_h = relocation_param_hash(:teacher_batch_year_ids)
      teacher_batch_h.each do |user_id, raw_ids|
        next if !current_user.superadmin? && user_id.to_s != current_user.id.to_s

        user = User.find_by(id: user_id)
        next if user.blank?

        ids = Array(raw_ids).reject(&:blank?).map { |v| resolve_relocation_batch_year_id(v) }.compact.uniq
        next if ids.blank?

        primary_id = ids.first
        primary = BatchYear.find_by(id: primary_id)
        next if primary.blank?

        user.update!(batch_year_id: primary.id, grade_id: primary.grade_id, resigned_at: nil)
        user.update!(extra_batch_year_ids: (ids - [ primary.id ]))
      end

      # Teacher books (single-cohort teachers): follow the teacher's primary assignment
      teacher_books = Book.where(id: pending_book_ids, source: :owned_by_teacher).where.not(user_id: nil).includes(:user).to_a
      teacher_books.group_by(&:user_id).each do |_uid, books|
        teacher = books.first&.user
        next if teacher.blank?
        next if teacher.member_batch_year_ids.size >= 2
        next if teacher.resigned?
        by = teacher.batch_year
        next if by.blank?
        Book.where(id: books.map(&:id)).update_all(batch_year_id: by.id, grade_id: by.grade_id)
      end

      # Resigned users (restorable within 1 month): assign batch to restore (HAK-41)
      resigned_assignments = relocation_param_hash(:resigned_assignments)
      resigned_assignments.each do |user_id, batch_year_id|
        next if batch_year_id.blank?
        user = User.find_by(id: user_id)
        next if user.blank? || !user.restore_allowed?
        batch_year = BatchYear.find_by(id: resolve_relocation_batch_year_id(batch_year_id))
        next if batch_year.blank?
        user.update!(batch_year_id: batch_year.id, grade_id: batch_year.grade_id, resigned_at: nil)
      end

      # New personnel (HAK-41): students only; 學號／座號可之後在人員管理補登
      Array(params[:new_personnel]).each do |p|
        name = p[:name].to_s.strip
        next if name.blank?
        ids = Array(p[:batch_year_ids]).reject(&:blank?).map { |v| resolve_relocation_batch_year_id(v) }.compact.uniq
        ids = [ resolve_relocation_batch_year_id(p[:batch_year_id]) ].compact if ids.blank? && p[:batch_year_id].to_s.strip.present?
        next if ids.blank?

        by = BatchYear.find_by(id: ids.first)
        next if by.blank?

        is_teacher = ids.size >= 2
        u = User.create!(name: name, id_number: nil, seat_number: nil, batch_year_id: by.id, grade_id: by.grade_id, admin: is_teacher, resigned_at: nil)
        u.update!(extra_batch_year_ids: (ids - [ by.id ])) if is_teacher
      end
    end

    clear_relocation_state!
    redirect_to batch_years_path, notice: "已儲存屆數指定。", status: :see_other
  end

  # Roll back stored school year and undo the latest class batch (cannot go earlier than the date-based current school year).
  def rollback_school_year
    before_roc = BatchYear.display_current_school_year_roc
    prev_roc = BatchYear.rollback_school_year!
    if prev_roc == before_roc
      redirect_to batch_years_path, alert: "不可返回超過目前實際學年度（#{BatchYear.current_school_year_roc}學年度）。", status: :see_other
    else
      redirect_to batch_years_path, notice: "已返回#{prev_roc}學年度。", status: :see_other
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
    RELOCATION_STATE_TTL = 12.hours
    RELOCATION_SESSION_KEYS = %i[
      pending_relocation_book_ids
      pending_relocation_user_ids
      relocation_draft
      relocation_draft_saved
      relocation_school_year_pending_commit
    ].freeze

    def relocation_state_cache_key
      "relocation_workflow/#{demo_mode? ? "demo" : "main"}/#{current_user.id}"
    end

    def relocation_state
      return @relocation_state if defined?(@relocation_state) && @relocation_state

      raw = Rails.cache.read(relocation_state_cache_key)
      @relocation_state = (raw.presence || {}).stringify_keys
    end

    def replace_relocation_state!(attrs)
      payload = attrs.deep_stringify_keys
      Rails.cache.write(relocation_state_cache_key, payload, expires_in: RELOCATION_STATE_TTL)
      @relocation_state = payload
      drop_relocation_session_payload!
    end

    def write_relocation_state!(attrs)
      replace_relocation_state!(relocation_state.merge(attrs.deep_stringify_keys))
    end

    def clear_relocation_state!
      Rails.cache.delete(relocation_state_cache_key)
      remove_instance_variable(:@relocation_state) if defined?(@relocation_state)
      drop_relocation_session_payload!
    end

    def drop_relocation_session_payload!
      RELOCATION_SESSION_KEYS.each { |key| session.delete(key) }
    end

    # Full advance + sync (persisted). Returns [pending_book_ids, pending_user_ids, next_roc].
    def advance_school_year_and_sync!
      BatchYear.advance_to_next_school_year!
      BatchYear.shift_stay_class_owned_books_to_previous_batch!
      next_roc = BatchYear.advance_stored_school_year!
      pending_book_ids = Book.needing_relocation_after_graduated_batch.pluck(:id)
      pending_user_ids = []

      Book.includes(:batch_year).find_each do |book|
        next if book.batch_year.blank?
        next if pending_book_ids.include?(book.id)
        next if book.owned_by_class? && book.stay?
        book.update_column(:grade_id, book.batch_year.grade_id)
      end

      User.includes(:batch_year).find_each do |user|
        if user.admin?
          pending_user_ids << user.id
          next
        end
        next if user.batch_year.blank?
        user.update_column(:grade_id, user.batch_year.grade_id)
      end

      [ pending_book_ids, pending_user_ids, next_roc ]
    end

    # Runs advance + sync inside a transaction and rolls back so DB and stored 學年度 stay unchanged.
    def dry_run_relocation_pending_ids
      pending_book_ids = nil
      pending_user_ids = nil
      ActiveRecord::Base.transaction do
        pending_book_ids, pending_user_ids, = advance_school_year_and_sync!
        raise ActiveRecord::Rollback
      end
      [ pending_book_ids, pending_user_ids ]
    end

    def relocation_param_hash(key)
      raw = params[key]
      return {} if raw.blank?
      return raw.to_unsafe_h if raw.is_a?(ActionController::Parameters)

      raw.to_h
    end

    def relocation_stringify_keys(h)
      return {} if h.blank?

      h.to_h.transform_keys(&:to_s)
    end

    # Every pending book must have an explicit new 屆數 (no silent "keep current batch").
    def relocation_book_assignments_error_message(pending_book_ids)
      return nil if pending_book_ids.blank?

      books = Book.where(id: pending_book_ids).to_a
      return nil if books.empty?

      book_h = relocation_param_hash(:book_assignments)
      teacher_batch_h = relocation_param_hash(:teacher_batch_year_ids)

      books.select { |b| b.owned_by_teacher? && b.user_id.present? }.group_by(&:user_id).each do |uid, tbooks|
        teacher = User.find_by(id: uid)
        linked = teacher&.member_batch_year_ids.to_a
        if linked.size >= 2
          allowed = teacher_batch_h[uid.to_s] || teacher_batch_h[uid] || teacher&.member_batch_year_ids || []
          allowed_ids = Array(allowed).reject(&:blank?).map(&:to_s)
          return "請為每位老師選擇至少一個屆數。" if allowed_ids.blank?
          tbooks.each do |book|
            v = book_h[book.id.to_s].presence || book_h[book.id]
            return "請為老師的每一本書選擇新屆數。" if v.blank?
            return "老師的書只能選擇該老師任教的屆數。" unless allowed_ids.include?(v.to_s)
          end
        else
          raw_ids = teacher_batch_h[uid.to_s] || teacher_batch_h[uid] || []
          ids = Array(raw_ids).reject(&:blank?)
          return "請為每位老師選擇至少一個屆數。" if ids.blank?
        end
      end

      books.reject { |b| b.owned_by_teacher? && b.user_id.present? }.each do |book|
        v = book_h[book.id.to_s].presence || book_h[book.id]
        return "請為每本需指定屆數的書選擇新屆數。" if v.blank?
      end

      nil
    end

    def persist_relocation_draft!
      new_personnel = Array(params[:new_personnel]).map do |p|
        p = p.to_unsafe_h if p.respond_to?(:to_unsafe_h)
        p.is_a?(Hash) ? p.slice("name", "batch_year_id", "batch_year_ids") : {}
      end
      new_personnel = normalize_new_personnel_rows(new_personnel)

      prev = relocation_state["draft"].presence || {}
      book_assignments = relocation_stringify_keys(relocation_param_hash(:book_assignments))
      resigned_assignments = relocation_stringify_keys(relocation_param_hash(:resigned_assignments))

      if current_user&.superadmin?
        teacher_batch_year_ids = relocation_stringify_keys(relocation_param_hash(:teacher_batch_year_ids))
        grade_teacher_ids = relocation_stringify_keys(relocation_param_hash(:grade_teacher_ids))
      else
        cid = current_user.id.to_s
        tb_raw = relocation_stringify_keys(relocation_param_hash(:teacher_batch_year_ids))
        own_picks = tb_raw[cid]

        prev_tb = relocation_stringify_keys(prev["teacher_batch_year_ids"] || {})
        if prev_tb.blank?
          prev_tb = User.where(id: Array(relocation_state["pending_user_ids"])).each_with_object({}) do |u, acc|
            acc[u.id.to_s] = u.member_batch_year_ids.map(&:to_s)
          end
        end
        teacher_batch_year_ids = prev_tb.merge(
          cid => Array(own_picks).flatten.compact.map(&:to_s).reject(&:blank?)
        )

        gt_raw = relocation_stringify_keys(relocation_param_hash(:grade_teacher_ids))
        prev_gt = relocation_stringify_keys(prev["grade_teacher_ids"] || {})
        sanitized_gt = {}
        gt_raw.each do |g, tid|
          t = tid.to_s.strip
          next if t.blank?
          next unless t == cid

          sanitized_gt[g.to_s] = t
        end
        grade_teacher_ids = prev_gt.merge(sanitized_gt)
      end

      write_relocation_state!(
        "draft" => {
          "book_assignments" => book_assignments,
          "teacher_batch_year_ids" => teacher_batch_year_ids,
          "grade_teacher_ids" => grade_teacher_ids,
          "resigned_assignments" => resigned_assignments,
          "new_personnel" => new_personnel
        }
      )
    end

    def set_batch_year
      @batch_year = BatchYear.find(params.expect(:id))
    end

    def batch_year_params
      params.expect(batch_year: [ :grade_id, :batch_number, :name ])
    end
end
