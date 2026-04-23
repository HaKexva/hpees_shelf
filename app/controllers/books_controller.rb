class BooksController < ApplicationController
  # 盤點表 PDF 排序（與列表「排序」選項一致：書名筆畫／來源／ISBN）
  INVENTORY_SORT_KEYS = %w[title_strokes source isbn].freeze

  before_action :set_book, only: %i[ show edit update destroy circulation_history return_to_library borrow return_shelf ]

  # GET /books or /books.json
  def index
    apply_current_batch_year_filter!
    remember_books_list_query!
    BatchYear.ensure_office_exists!
    @list_sort = Book.list_sort_from_param(params[:sort])
    @books = filtered_books_scope.includes(:batch_year, :borrowers, :user).merge(Book.ordered_for_list(@list_sort))
    @batch_years = BatchYear.by_number_desc
    @filter_batch_year_id = params[:batch_year_id]
    @filter_q = params[:q].to_s.strip.presence
    @filter_source = _canonical_books_list_source_param(params[:source])
    @filter_status = params[:status].presence
    @inventory_sort = params[:inventory_sort].presence_in(INVENTORY_SORT_KEYS) || "isbn"
    teacher_ids = Book.where(source: :owned_by_teacher).where.not(user_id: nil).distinct.pluck(:user_id)
    @inventory_teacher_users = User.with_deleted.where(id: teacher_ids).order(:name)
    @bulk_source_teacher_users = User.active.where(admin: true).order(:name)
    @invalid_books = @books.select { |b| b.missing_required_fields.any? }
    @books_with_invalid_isbn = @books.select(&:invalid_isbn?)
    @any_library_books_to_return = @filter_batch_year_id.present? &&
      Book.where(source: :owned_by_library, batch_year_id: @filter_batch_year_id)
          .where.not(status: Book::STATUS_RETURNED_LIBRARY).exists?
    # 借閱超過一天視為失蹤，在頁面上方列出
    @missing_books = Book.where.not(title: [ nil, "" ])
                         .where.not(status: Book::STATUS_RETURNED_LIBRARY)
                         .overdue_as_missing
                         .includes(:batch_year, :borrowers, :user)
                         .order(borrowed_at: :asc)
  end

  # GET /books/export — CSV using `filtered_books_scope` + `sort` (same query params as `/books`).
  def export
    apply_current_batch_year_filter!
    BatchYear.ensure_office_exists!
    sort = Book.list_sort_from_param(params[:sort])
    books = filtered_books_scope.includes(:batch_year, :user).merge(Book.ordered_for_list(sort))
    bom = "\uFEFF"
    headers = %w[書名 ISBN 屆數ID 屆數 來源 老師 班級書 登錄號 總數 冊數 備註 狀態]
    csv = +""
    csv << bom
    csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
    books.find_each do |book|
      row = [
        book.title,
        helpers.format_isbn13(book.isbn),
        book.batch_year_id.to_s,
        book.batch_year&.display_label_with_grade.to_s,
        book.source.present? ? I18n.t("activerecord.enums.book.source.#{book.source}") : "",
        (book.owned_by_teacher? && book.user.present? ? book.user.name.to_s : ""),
        (book.owned_by_class? && book.relocation_behavior.present? ? I18n.t("activerecord.enums.book.relocation_behavior_short.#{book.relocation_behavior}") : ""),
        book.call_number.to_s,
        book.total.to_s,
        book.volume.to_s,
        book.note.to_s,
        book.display_status
      ]
      csv << row.map { |c| _csv_escape(c) }.join(",") << "\n"
    end
    filename = "books_export_#{Time.zone.now.strftime('%Y%m%d_%H%M')}.csv"
    send_data csv, filename: filename, type: "text/csv; charset=utf-8"
  end

  # GET /books/inventory_pdf — 盤點表 PDF（需選屆數；沿用列表篩選；排序見 inventory_sort）
  def inventory_pdf
    apply_current_batch_year_filter!
    BatchYear.ensure_office_exists!
    batch_year_id = params[:batch_year_id].presence
    if batch_year_id.blank?
      redirect_to books_path(_books_list_query_params), alert: "請先選擇屆數。", status: :see_other
      return
    end

    batch_year = BatchYear.find_by(id: batch_year_id)
    unless batch_year
      redirect_to books_path(_books_list_query_params), alert: "找不到該屆數。", status: :see_other
      return
    end

    inventory_sort = params[:inventory_sort].presence_in(INVENTORY_SORT_KEYS) || "isbn"
    inventory_source = params[:inventory_source].presence
    if inventory_source.blank?
      redirect_to books_path(_books_list_query_params), alert: "請先選擇來源。", status: :see_other
      return
    end

    books = _inventory_pdf_filtered_scope(batch_year.id)
    books, source_title_suffix, specific_source = _apply_inventory_source_filter(books, inventory_source)
    books = _inventory_pdf_ordered_scope(books, inventory_sort)
    books = books.includes(:user)

    # If user chose a specific source (not 全部 / not 所有老師的書), omit the source column.
    show_source_column = !specific_source

    pdf_data = Books::InventoryPdf.render(
      books.to_a,
      batch_year: batch_year,
      show_source_column: show_source_column,
      source_title_suffix: source_title_suffix
    )
    filename = "inventory_batch#{batch_year.batch_number}_#{Time.zone.now.strftime('%Y%m%d_%H%M')}.pdf"
    send_data pdf_data, filename: filename, type: "application/pdf", disposition: "attachment"
  end

  # GET /books/import
  # POST /books/import
  def import
    BatchYear.ensure_office_exists!
    @import_book_preview_ready = false
    @imported_data = []
    @headers = []
    @required_columns = %w[title isbn source]
    @expected_columns = %w[title isbn batch_year_id batch_year total volume note source call_number status]
    @column_names_zh = {
      "title" => "書名",
      "isbn" => "ISBN",
      "batch_year_id" => "屆數ID",
      "batch_year" => "屆數",
      "total" => "總數",
      "volume" => "冊數",
      "note" => "備註",
      "source" => "來源",
      "call_number" => "登錄號",
      "status" => "狀態"
    }

    return unless request.post?

    if params[:export_invalid] == "true" && params[:import_data].present?
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_import_row_edits!(import_data, params[:edit_rows])

      invalid_rows = []
      import_data.each do |row|
        title = _import_row_value(row, "title", "Title", "書名")
        isbn = _import_row_isbn(row)
        source = _import_row_value(row, "source", "Source", "來源")
        next unless _import_book_row_invalid?(row)

        invalid_rows << {
          "書名" => title.presence || "請填寫",
          "ISBN" => isbn.presence || "請填寫",
          "屆數ID" => _import_row_value(row, "batch_year_id", "屆數ID").to_s.strip.presence,
          "屆數" => _import_row_value(row, "batch_year", "屆數").to_s.strip.presence,
          "來源" => source.presence || "請填寫",
          "登錄號" => _import_row_value(row, "call_number", "登錄號").to_s.strip.presence,
          "總數" => _import_row_value(row, "total", "Total", "總數").to_s.strip.presence,
          "冊數" => _import_row_value(row, "volume", "Volume", "冊數").to_s.strip.presence,
          "備註" => _import_row_value(row, "note", "Note", "備註").to_s.strip.presence,
          "狀態" => _import_row_value(row, "status", "狀態", "Status").to_s.strip.presence
        }
      end

      headers = %w[書名 ISBN 屆數ID 屆數 來源 登錄號 總數 冊數 備註 狀態]
      bom = "\uFEFF"
      csv = +""
      csv << bom
      csv << headers.map { |h| _csv_escape(h) }.join(",") << "\n"
      invalid_rows.each do |r|
        csv << headers.map { |h| _csv_escape(r[h]) }.join(",") << "\n"
      end

      filename = "books_import_invalid_#{Time.zone.now.strftime('%Y%m%d_%H%M')}.csv"
      send_data csv, filename: filename, type: "text/csv; charset=utf-8"
    elsif params[:refresh_preview] == "true" && params[:import_data].present?
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_import_row_edits!(import_data, params[:edit_rows])
      _restore_import_preview(import_data, params[:batch_year_id].presence&.to_i)
      render :import
    elsif params[:confirm] == "true" && params[:import_data].present?
      # Confirm import from hidden field data (Base64 encoded JSON)
      require "json"
      require "base64"
      import_data = JSON.parse(Base64.strict_decode64(params[:import_data]))
      _apply_import_row_edits!(import_data, params[:edit_rows])

      selected_batch_year_id = params[:batch_year_id].presence&.to_i
      selected_batch_year_id = nil if selected_batch_year_id.blank? || selected_batch_year_id < 1

      if selected_batch_year_id.nil?
        needs_fallback = import_data.each_with_index.any? do |row, _idx|
          next false if _import_book_row_invalid?(row)

          eff = _import_book_batch_year_id_for_row(row, nil)
          eff.nil? || eff < 1
        end
        if needs_fallback
          _restore_import_preview(import_data, params[:batch_year_id].presence&.to_i)
          @batch_years = BatchYear.by_number_desc
          flash.now[:alert] = "請選擇屆數，或在檔案中為每一筆提供有效的「屆數ID」或「屆數」。"
          render :import, status: :unprocessable_entity
          return
        end
      end

      imported_count = 0
      skipped_count = 0
      invalid_skipped_count = 0
      save_failed_count = 0
      duplicate_action = params[:duplicate_action] || "skip"
      selected_duplicates = (params[:selected_duplicates] || []).map(&:to_i)

      import_data.each_with_index do |row, index|
        if _import_book_row_invalid?(row)
          invalid_skipped_count += 1
          next
        end

        effective_batch_year_id = _import_book_batch_year_id_for_row(row, selected_batch_year_id)
        if effective_batch_year_id.nil? || effective_batch_year_id < 1
          invalid_skipped_count += 1
          next
        end

        batch_year = BatchYear.find_by(id: effective_batch_year_id)

        title = _import_row_value(row, "title", "Title", "書名")
        isbn = _import_row_isbn(row)
        source_raw = _import_row_value(row, "source", "Source", "來源")
        source_key = Book.import_source_key_from_label(source_raw)
        total_raw = _import_row_value(row, "total", "Total", "總數")
        total_value = total_raw.present? && total_raw.to_s.strip.present? ? total_raw.to_s.to_i : 1
        total_value = 1 if total_value < 1
        # 圖書館館藏：總數不允許 > 1（避免 CSV 匯入錯誤設定）
        if source_key == "owned_by_library" && total_value > 1
          Rails.logger.warn "Skip library book with total > 1 in import (index #{index}, ISBN #{isbn}, total #{total_value})"
          skipped_count += 1
          next
        end

        book_attrs = {
          title: title,
          isbn: isbn,
          total: total_value,
          volume: _import_row_value(row, "volume", "Volume", "冊數"),
          note: _import_row_value(row, "note", "Note", "備註"),
          source: source_key,
          grade_id: batch_year&.grade_id,
          batch_year_id: effective_batch_year_id
        }
        status_for_import = _import_book_status_for_save(row)
        book_attrs[:status] = status_for_import if status_for_import.present?
        if source_key == "owned_by_library"
          call_num = _import_row_value(row, "call_number", "登錄號")
          book_attrs[:call_number] = call_num.to_s.strip.presence if call_num.present?
        end
        if source_key == "owned_by_teacher"
          teacher = Book.import_teacher_user_from_source_label(source_raw)
          book_attrs[:user_id] = teacher.id if teacher
        end

        # Duplicate only when same batch_year and title, isbn, source (and for library: call_number) all match
        existing = _import_find_existing(row, title, isbn, source_key, effective_batch_year_id)
        is_duplicate = existing.present?

        if is_duplicate
          case duplicate_action
          when "skip"
            skipped_count += 1
            next
          when "select"
            unless selected_duplicates.include?(index)
              skipped_count += 1
              next
            end
            # 勾選保留重複書籍：總數加一，不建立新檔案
            existing.update_column(:total, existing.total.to_i + 1)
            imported_count += 1
            next
          end
        end

        book = Book.new(book_attrs)
        if book.save
          imported_count += 1
        else
          save_failed_count += 1
          Rails.logger.error "Failed to save book: #{book.errors.full_messages.join(', ')}"
        end
      end

      message = "成功匯入 #{imported_count} 本書籍。"
      message += " 已跳過 #{skipped_count} 本重複書籍。" if skipped_count > 0
      message += " 已跳過 #{invalid_skipped_count} 筆不符合的資料。" if invalid_skipped_count > 0
      if save_failed_count.positive?
        message += " 有 #{save_failed_count} 筆因欄位錯誤未能寫入（常見原因：圖書館館藏缺 8 碼登錄號或格式錯誤）。"
      end
      redirect_to books_path(books_list_query_hash), notice: message, status: :see_other
    elsif params[:file].present?
      # Preview uploaded file: parsing lives in BooksImport::UploadParser (CSV encoding vs Excel binary).
      file = params[:file]
      begin
        @headers, rows = BooksImport::UploadParser.call(file)
        @imported_data = rows.reject do |row|
          row.values.all? { |v| v.nil? || v.to_s.strip.empty? }
        end

        # Check for column mismatches (match by column name, order does not matter; both English and Chinese headers are accepted)
        headers_downcase = @headers.map { |h| h&.to_s&.strip }
        normalized_headers = headers_downcase.map { |h| _normalize_book_csv_header_value(h) }.compact
        @missing_columns = @required_columns - normalized_headers
        @extra_columns = normalized_headers.compact - @expected_columns

        # When headers are valid: validate each row against import format (title required); invalid rows show "不符合" in the preview status column
        @invalid_row_indices = []
        @imported_data.each_with_index do |row, index|
          @invalid_row_indices << index if _import_book_row_invalid?(row)
        end

        # DB duplicate preview only after user selects 屆數 and clicks「套用屆數更新預覽」(same batch_year = same book for deduping)
        _rebuild_book_import_duplicate_preview!(nil)

        @batch_years = BatchYear.by_number_desc
        render :import
      rescue StandardError => e
        flash.now[:alert] = "解析檔案時發生錯誤：#{e.message}"
        render :import
      end
    else
      flash.now[:alert] = "請選擇要上傳的檔案。"
      render :import
    end
  end

  # GET /books/1 or /books/1.json
  def show
    redirect_to edit_book_path(@book), status: :see_other
  end

  # GET /books/1/circulation_history — circulation rows for this book (借閱紀錄)
  def circulation_history
    @circulation_records = @book.circulation_records.includes(:user).order(borrowed_at: :desc).limit(500)
  end

  # GET /books/new
  def new
    @book = Book.new
    @batch_years = _batch_year_options_for_book_forms
    @admin_users = User.active.where(admin: true).order(:name)
  end

  # GET /books/1/edit
  def edit
    @batch_years = _batch_year_options_for_book_forms
    @admin_users = User.active.where(admin: true).order(:name)
  end

  # POST /books or /books.json
  def create
    @book = Book.new(book_params)
    # Grade is derived from the selected batch_year
    @book.grade_id = @book.batch_year&.grade_id if @book.batch_year_id.present? && @book.grade_id.blank?
    @book.user_id = nil unless @book.owned_by_teacher? || @book.owned_by_library?

    respond_to do |format|
      if @book.save
        format.html { redirect_to books_path(books_list_query_hash), notice: "書籍已建立。", status: :see_other }
        format.json { render :show, status: :created, location: @book }
      else
        @batch_years = _batch_year_options_for_book_forms
        @admin_users = User.active.where(admin: true).order(:name)
        flash.now[:alert] = @book.errors.full_messages.join("；")
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /books/1 or /books/1.json
  def update
    attrs = book_params
    attrs[:user_id] = nil unless attrs[:source].to_s == "owned_by_teacher" || attrs[:source].to_s == "owned_by_library"
    respond_to do |format|
      if @book.update(attrs)
        # When batch_year changes, optionally sync grade (if grade was not changed in the form, derive from batch_year)
        @book.update_column(:grade_id, @book.batch_year&.grade_id) if @book.batch_year_id.present?
        format.html { redirect_to books_path(books_list_query_hash), notice: "書籍已更新。", status: :see_other }
        format.json { render :show, status: :ok, location: @book }
      else
        @batch_years = _batch_year_options_for_book_forms
        @admin_users = User.active.where(admin: true).order(:name)
        flash.now[:alert] = @book.errors.full_messages.join("；")
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @book.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /books/1 or /books/1.json
  def destroy
    @book.destroy!

    respond_to do |format|
      format.html { redirect_to books_path(books_list_query_hash), notice: "書籍已刪除。", status: :see_other }
      format.json { head :no_content }
    end
  end

  # POST /books/borrow_by_isbn — Borrow by scanned/entered ISBN (借書掃 ISBN)
  def borrow_by_isbn
    isbn = params[:isbn].to_s.strip
    user_id = params[:user_id].presence&.to_i
    user = User.find_by(id: user_id)
    unless user
      redirect_to root_path, alert: "請選擇借閱人。", status: :see_other
      return
    end
    if isbn.blank?
      redirect_to root_path, alert: "請掃描或輸入 ISBN。", status: :see_other
      return
    end
    # 這個舊的借書入口也改成看所有來源；圖書館館藏若總數大於 1，可借到沒有可用冊數為止
    candidates =
      Book.where.not(status: Book::STATUS_RETURNED_LIBRARY)
          .where("TRIM(COALESCE(isbn, '')) = ?", isbn)
          .where.not(title: [ nil, "" ])
          .includes(:batch_year, :borrowers)
          .to_a

    in_batch = candidates.select { |b| user.may_borrow_from_batch?(b.batch_year_id) }
    book = in_batch.find(&:available_for_checkout?)

    unless book
      alert_msg =
        if candidates.empty?
          "找不到架上且符合此 ISBN 的圖書館館藏（ISBN：#{isbn}）。"
        elsif in_batch.empty?
          "找不到符合此 ISBN 且在借閱人可借屆數內的可借書籍（ISBN：#{isbn}）。"
        else
          "找不到架上且符合此 ISBN 的圖書館館藏（可能已無可借冊數）（ISBN：#{isbn}）。"
        end
      redirect_to root_path, alert: alert_msg, status: :see_other
      return
    end

    if book.owned_by_library? && book.effective_total > 1
      if book.can_borrow_copy?
        book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
        book.update!(status: Book::STATUS_BORROWED, borrowed_at: Time.current)
      else
        redirect_to root_path, alert: "此書已無可借冊數。", status: :see_other
        return
      end
    else
      book.checkout_to_borrower!(user)
    end
    redirect_to root_path, notice: "已登記借閱：#{book.title} → #{user.name}。", status: :see_other
  end

  # POST /books/1/borrow — Library book: set borrower (借書)
  def borrow
    unless @book.owned_by_library?
      redirect_to root_path, alert: "僅圖書館館藏可借閱。", status: :see_other
      return
    end
    unless @book.available_for_checkout?
      redirect_to root_path, alert: "此書已無可借冊數或不在架上。", status: :see_other
      return
    end
    user_id = params[:user_id].presence&.to_i
    user = User.find_by(id: user_id)
    unless user
      redirect_to root_path, alert: "請選擇借閱人。", status: :see_other
      return
    end
    unless user.may_borrow_from_batch?(@book.batch_year_id)
      redirect_to root_path, alert: "此書的屆數不在借閱人可借範圍內。", status: :see_other
      return
    end
    if @book.owned_by_library? && @book.effective_total > 1
      @book.circulation_records.create!(user_id: user.id, borrowed_at: Time.current)
      @book.update!(status: Book::STATUS_BORROWED, borrowed_at: Time.current)
    else
      @book.checkout_to_borrower!(user)
    end
    redirect_to root_path, notice: "已登記借閱：#{@book.title} → #{user.name}。", status: :see_other
  end

  # POST /books/1/return_shelf — Mark book as returned (還書); supports all sources (library, donated, class, teacher)
  def return_shelf
    if @book.owned_by_library? && @book.effective_total > 1
      # 強制將所有未還的冊數一併標記為已還
      @book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
      @book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
    else
      @book.return_from_single_copy_borrow!
    end
    redirect_to root_path, notice: "已還書：#{@book.title}。", status: :see_other
  end

  # POST /books/1/return_to_library — Library books: save borrow history then soft-delete the book (HAK-75)
  def return_to_library
    if @book.owned_by_library?
      LibraryLoanHistory.create!(
        book_id: @book.id,
        book_title: @book.title.to_s.presence || "（無書名）",
        book_isbn: @book.isbn,
        borrowed_at: @book.borrowed_at,
        returned_at: Time.current,
        batch_year_id: @book.batch_year_id
      )
      @book.return_to_library_and_soft_delete!
      redirect_to books_path(books_list_query_hash), notice: "已歸還圖書館；書籍已標記為「歸還圖書館」並自列表隱藏，借閱紀錄已保留。", status: :see_other
    else
      redirect_to @book, alert: "僅圖書館的書可執行此操作。", status: :see_other
    end
  end

  # GET /books/return_to_library_batch — Choose which batch's library books to mark as returned
  def return_to_library_batch
    @batch_years = _batch_year_options_for_book_forms
  end

  # POST /books/apply_return_to_library_batch — Save borrow history for each library book then soft-delete (HAK-75)
  def apply_return_to_library_batch
    raw = params[:batch_year_id].to_s
    scope = Book.where(source: :owned_by_library)
    scope = scope.where(batch_year_id: raw.to_i) if raw.present? && raw != "all"

    if raw.blank?
      redirect_to return_to_library_batch_books_path, alert: "請選擇屆數（或全部）。", status: :see_other
      return
    end

    count = 0
    scope.find_each do |book|
      LibraryLoanHistory.transaction do
        LibraryLoanHistory.create!(
          book_id: book.id,
          book_title: book.title.to_s.presence || "（無書名）",
          book_isbn: book.isbn,
          borrowed_at: book.borrowed_at,
          returned_at: Time.current,
          batch_year_id: book.batch_year_id
        )
        book.return_to_library_and_soft_delete!
      end
      count += 1
    end

    label = raw == "all" ? "全部屆數" : "該屆"
    redirect_to books_path(books_list_query_hash), notice: "已將#{label} #{count} 本圖書館的書歸還圖書館；書籍已自列表隱藏，借閱紀錄與資料已保留。", status: :see_other
  end

  # DELETE /books/bulk_destroy
  def bulk_destroy
    ids = Array(params[:book_ids]).reject(&:blank?).map(&:to_i)
    rq = books_bulk_redirect_query
    if ids.any?
      now = Time.current
      count = Book.where(id: ids).update_all(deleted_at: now, updated_at: now)
      redirect_to books_path(rq), notice: "已刪除 #{count} 本書籍。", status: :see_other
    else
      redirect_to books_path(rq), alert: "請至少選擇一本書。", status: :see_other
    end
  end

  # POST /books/bulk_update_source
  def bulk_update_source
    ids = Array(params[:book_ids]).reject(&:blank?).map(&:to_i)
    rq = books_bulk_redirect_query
    source = params[:new_source].to_s.strip
    teacher_user_id = params[:teacher_user_id].to_s.strip.to_i

    allowed_sources = %w[owned_by_library donated owned_by_class owned_by_teacher].freeze
    unless allowed_sources.include?(source)
      redirect_to books_path(rq), alert: "請選擇可變更的來源。", status: :see_other
      return
    end

    if ids.empty?
      redirect_to books_path(rq), alert: "請至少選擇一本書。", status: :see_other
      return
    end

    if Book.where(id: ids, status: Book::STATUS_BORROWED).exists?
      redirect_to books_path(rq), alert: "借閱中的書不可批次變更來源。", status: :see_other
      return
    end

    teacher =
      if source == "owned_by_teacher"
        User.active.find_by(id: teacher_user_id, admin: true)
      end
    if source == "owned_by_teacher" && teacher.blank?
      redirect_to books_path(rq), alert: "請先選擇要指派的老師。", status: :see_other
      return
    end

    now = Time.current
    count = 0
    begin
      Book.where(id: ids).includes(:user).find_each do |book|
        attrs = { source: source, updated_at: now }
        if source == "owned_by_teacher"
          attrs[:user_id] = teacher.id
        elsif book.owned_by_teacher?
          attrs[:user_id] = nil
        end
        book.update!(attrs)
        count += 1
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to books_path(rq), alert: e.record.errors.full_messages.first.presence || "來源變更失敗。", status: :see_other
      return
    end
    redirect_to books_path(rq), notice: "已更新 #{count} 本書的來源。", status: :see_other
  end

  private
    def _batch_year_options_for_book_forms
      BatchYear.ensure_office_exists!
      return BatchYear.class_batches_by_number_desc if current_user.superadmin?

      ids = current_user.member_batch_year_ids
      ids = [ current_user.batch_year_id ].compact if ids.blank?
      BatchYear.where(id: ids).order(batch_number: :desc)
    end

    def _apply_import_row_edits!(import_data, edit_rows_param)
      return if import_data.blank? || edit_rows_param.blank?

      edit_rows =
        if edit_rows_param.respond_to?(:to_unsafe_h)
          edit_rows_param.to_unsafe_h
        else
          edit_rows_param.to_h
        end

      import_data.each_with_index do |row, idx|
        edits = edit_rows[idx.to_s] || edit_rows[idx]
        next if edits.blank?

        _apply_one_import_row_edit!(row, edits.to_h)
      end
    end

    def _apply_one_import_row_edit!(row, edits)
      return if row.blank? || edits.blank?

      map = {
        title: %w[title Title 書名],
        isbn: %w[isbn ISBN 國際標準書號],
        batch_year_id: %w[batch_year_id 屆數ID],
        batch_year: %w[batch_year 屆數],
        source: %w[source Source 來源],
        total: %w[total Total 總數],
        volume: %w[volume Volume 冊數],
        note: %w[note Note 備註],
        call_number: %w[call_number 登錄號],
        status: %w[status Status 狀態]
      }

      map.each do |field, keys|
        next unless edits.key?(field.to_s)

        v = edits[field.to_s].to_s.strip

        # Allow clearing values: keep blank edits as blank.
        # This lets users remove a wrong value and re-check validation.
        if v.blank?
          k = keys.find { |kk| row.key?(kk) } || keys.first
          row[k] = ""
          next
        end

        # Update whichever key exists in this row; otherwise prefer the first key.
        k = keys.find { |kk| row.key?(kk) } || keys.first
        row[k] = v
      end
    end
    def _inventory_pdf_filtered_scope(batch_year_id)
      books = Book.where.not(title: [ nil, "" ])
      if params[:status].present?
        books = books.where(status: params[:status])
      else
        books = books.where.not(status: Book::STATUS_RETURNED_LIBRARY)
      end
      books = books.where(batch_year_id: batch_year_id)

      q_raw = params[:q].to_s.strip
      if q_raw.present?
        pattern = "%#{Book.sanitize_sql_like(q_raw)}%"
        digits = q_raw.gsub(/\D/, "")
        if digits.present?
          isbn_pattern = "%#{Book.sanitize_sql_like(digits)}%"
          tn = Book.table_name
          qc = Book.connection
          isbn_norm = "REPLACE(REPLACE(TRIM(COALESCE(#{qc.quote_table_name(tn)}.#{qc.quote_column_name("isbn")}, '')), '-', ''), ' ', '')"
          books = books.where("title LIKE ? OR #{isbn_norm} LIKE ?", pattern, isbn_pattern)
        else
          books = books.where("title LIKE ?", pattern)
        end
      end

      books
    end

    def _apply_inventory_source_filter(books, inventory_source)
      case inventory_source
      when "all"
        [ books, "全部", false ]
      when "teachers_all"
        [ books.where(source: :owned_by_teacher), "所有老師的書", false ]
      when /\Ateacher:(\d+)\z/
        teacher_id = Regexp.last_match(1).to_i
        teacher = User.with_deleted.find_by(id: teacher_id)
        label = teacher&.name.present? ? "#{teacher.name}老師的書" : I18n.t("activerecord.enums.book.source.owned_by_teacher")
        [ books.where(source: :owned_by_teacher, user_id: teacher_id), label, true ]
      when Book::LIST_SOURCE_OWNED_BY_CLASS_STAY
        [ books.where(source: :owned_by_class, relocation_behavior: :stay), I18n.t("books.list_source.owned_by_class_stay"), true ]
      when Book::LIST_SOURCE_OWNED_BY_CLASS_MOVE
        [ books.where(source: :owned_by_class, relocation_behavior: :move_with_class), I18n.t("books.list_source.owned_by_class_move_with_class"), true ]
      else
        # Enum key (owned_by_library / donated / owned_by_class / owned_by_teacher)
        if Book.sources.key?(inventory_source)
          [ books.where(source: inventory_source), I18n.t("activerecord.enums.book.source.#{inventory_source}"), true ]
        else
          [ books, "全部", false ]
        end
      end
    end

    def _inventory_pdf_ordered_scope(books, inventory_sort)
      if Book.respond_to?(:ordered_for_list)
        books.merge(Book.ordered_for_list(inventory_sort))
      else
        case inventory_sort
        when "source" then books.order(:source)
        when "isbn" then books.order(:isbn)
        else books.order(:title)
        end
      end
    end

    def _books_list_query_params
      params.permit(:batch_year_id, :q, :source, :status, :sort, :inventory_sort).to_h.compact_blank
    end

    # Legacy list URL `source=owned_by_teacher` (generic label) matches `teachers_all`; the index dropdown only offers 所有老師的書 + per-teacher.
    def _canonical_books_list_source_param(raw)
      s = raw.to_s.strip
      return nil if s.blank?

      (s == "owned_by_teacher") ? "teachers_all" : s
    end

    # List + CSV export: `source` is enum keys, `teachers_all` / `teacher:<id>`, or `owned_by_class:stay` / `owned_by_class:move_with_class` (班級的書 × 切換; inventory PDF same).
    def _filter_books_by_list_source_param(books, raw)
      s = raw.to_s.strip
      return books if s.blank?

      case s
      when "teachers_all"
        books.where(source: :owned_by_teacher)
      when /\Ateacher:(\d+)\z/
        books.where(source: :owned_by_teacher, user_id: Regexp.last_match(1).to_i)
      when Book::LIST_SOURCE_OWNED_BY_CLASS_STAY
        books.where(source: :owned_by_class, relocation_behavior: :stay)
      when Book::LIST_SOURCE_OWNED_BY_CLASS_MOVE
        books.where(source: :owned_by_class, relocation_behavior: :move_with_class)
      else
        Book.sources.key?(s) ? books.where(source: s) : books
      end
    end

    def filtered_books_scope
      books = Book.where.not(title: [ nil, "" ])
      if params[:status].present?
        books = books.where(status: params[:status])
      else
        books = books.where.not(status: Book::STATUS_RETURNED_LIBRARY)
      end
      if params[:source].present?
        books = _filter_books_by_list_source_param(books, _canonical_books_list_source_param(params[:source]))
      end
      books = books.where(batch_year_id: params[:batch_year_id]) if params[:batch_year_id].present?
      q_raw = params[:q].to_s.strip
      if q_raw.present?
        pattern = "%#{Book.sanitize_sql_like(q_raw)}%"
        digits = q_raw.gsub(/\D/, "")
        if digits.present?
          isbn_pattern = "%#{Book.sanitize_sql_like(digits)}%"
          tn = Book.table_name
          qc = Book.connection
          isbn_norm = "REPLACE(REPLACE(TRIM(COALESCE(#{qc.quote_table_name(tn)}.#{qc.quote_column_name("isbn")}, '')), '-', ''), ' ', '')"
          books = books.where("title LIKE ? OR #{isbn_norm} LIKE ?", pattern, isbn_pattern)
        else
          books = books.where("title LIKE ?", pattern)
        end
      end
      books
    end

    def _normalize_book_csv_header_value(value)
      Book.normalize_import_csv_header(value)
    end

    def _decode_csv_to_utf8_books(raw)
      required = @required_columns || %w[title isbn source]
      strip_bom = ->(s) { s.delete_prefix("\uFEFF") }

      header_matches_required = lambda do |decoded|
        header_line = decoded.lines.first.to_s
        headers = _parse_csv_line(header_line)
        normalized = headers.map { |h| _normalize_book_csv_header_value(h) }.compact
        (required - normalized).empty?
      end

      # 1) Prefer real UTF-8 if valid.
      utf8 = raw.dup.force_encoding("UTF-8")
      if utf8.valid_encoding?
        decoded = strip_bom.call(utf8.encode("UTF-8"))
        return decoded if header_matches_required.call(decoded)
      end

      # 2) Try common encodings for Excel/Sheets exports.
      candidates = [
        -> { raw.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("CP950").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("Big5").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") }
      ]

      candidates.each do |decoder|
        begin
          decoded = strip_bom.call(decoder.call)
          return decoded if header_matches_required.call(decoded)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          next
        end
      end

      # 3) Last resort: UTF-8 with replacement.
      strip_bom.call(raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: ""))
    end

    def set_book
      @book = Book.find(params[:id])
    end

    def book_params
      params.require(:book).permit(
        :title,
        :isbn,
        :total,
        :volume,
        :note,
        :source,
        :relocation_behavior,
        :borrowed_at,
        :edition_part,
        :batch_year_id,
        :grade_id,
        :user_id,
        :call_number,
        :relocation_behavior
      )
    end

    # Read a value from an import row by column name, order-independent; supports both English and Chinese headers
    def _import_row_value(row, *keys)
      Book.lookup_import_row_value(row, *keys)
    end

    def _import_row_isbn(row)
      Book.import_row_isbn_digits(row)
    end

    # Per-row 屆數: explicit 屆數ID wins, then 屆數 label; otherwise `fallback_id`. Returns -1 when CSV has an invalid id/label.
    def _import_book_batch_year_id_for_row(row, fallback_id)
      id_raw = Book.lookup_import_row_value(row, "batch_year_id", "屆數ID", "Batch_year_id")
      if id_raw.present?
        stripped = id_raw.to_s.strip
        if stripped.match?(/\A\d+\z/)
          i = stripped.to_i
          return i if i.positive? && BatchYear.exists?(id: i)

          return -1
        end

        return -1
      end

      lab = Book.lookup_import_row_value(row, "batch_year", "屆數", "Batch_year")
      if lab.present?
        bid = BatchYear.find_id_from_import_label(lab)
        return bid if bid.present?

        return -1
      end

      fb = fallback_id.to_i
      fb.positive? ? fb : nil
    end

    def _import_book_status_invalid?(row)
      raw = Book.lookup_import_row_value(row, "status", "狀態", "Status")
      return false if raw.blank?

      !_import_book_status_string_valid?(raw.to_s.strip)
    end

    def _import_book_status_string_valid?(s)
      return true if [ Book::STATUS_ON_SHELF, Book::STATUS_MISSING, Book::STATUS_RETURNED_LIBRARY ].include?(s)
      return true if s.start_with?(Book::STATUS_BORROWED)

      false
    end

    def _import_book_status_for_save(row)
      raw = Book.lookup_import_row_value(row, "status", "狀態", "Status")
      return nil if raw.blank?

      s = raw.to_s.strip
      return Book::STATUS_BORROWED if s.start_with?(Book::STATUS_BORROWED)

      s.presence
    end

    # Same rules as import preview: required title / ISBN / source, valid ISBN-13; library rows need 8-digit 登錄號.
    def _import_book_row_invalid?(row)
      title = _import_row_value(row, "title", "Title", "書名")
      isbn = _import_row_isbn(row)
      source = _import_row_value(row, "source", "Source", "來源")
      return true if title.blank? || source.blank? || isbn.blank? || !Book.valid_isbn13?(isbn)

      source_key = Book.import_source_key_from_label(source)
      if source_key == "owned_by_library"
        call_num = _import_row_value(row, "call_number", "登錄號").to_s.strip
        return true if call_num.blank? || !call_num.match?(/\A\d{8}\z/)
      end
      if source_key == "owned_by_teacher"
        return true if Book.import_teacher_user_from_source_label(source).nil?
      end

      bid = _import_book_batch_year_id_for_row(row, nil)
      return true if bid == -1

      return true if _import_book_status_invalid?(row)

      false
    end

    # Find existing book in the same 屆數:
    # - same batch_year, title, isbn, source
    # - same volume / edition_part (so 上下冊 are treated as different books)
    # - for library also same call_number.
    def _import_find_existing(row, title, isbn, source_key, batch_year_id)
      return nil if batch_year_id.blank?

      scope = Book.where(title: title, isbn: isbn, source: source_key, batch_year_id: batch_year_id)
      vol = _import_row_value(row, "volume", "Volume", "冊數").to_s.strip.presence
      ed = _import_row_value(row, "edition_part", "Edition_part", "版次", "分冊").to_s.strip.presence
      scope = scope.where(volume: vol, edition_part: ed)
      if source_key == "owned_by_library"
        call_num = _import_row_value(row, "call_number", "登錄號")
        scope = scope.where(call_number: call_num.to_s.strip.presence)
      end
      scope.first
    end

    # Rebuild @duplicates / @new_books for preview; pass nil until user selects 屆數 and refreshes.
    def _rebuild_book_import_duplicate_preview!(batch_year_id)
      @preview_batch_year_id = batch_year_id
      headers_stripped = @headers.map { |h| h&.to_s&.strip }
      normalized_headers = headers_stripped.map { |h| _normalize_book_csv_header_value(h) }.compact
      has_title_column = normalized_headers.include?("title")
      has_isbn_column = normalized_headers.include?("isbn")

      @duplicates = []
      @new_books = []
      fallback = batch_year_id.present? && batch_year_id.to_i >= 1 ? batch_year_id.to_i : nil

      if has_title_column && has_isbn_column
        @imported_data.each_with_index do |row, index|
          next if (@invalid_row_indices || []).include?(index)

          title = _import_row_value(row, "title", "Title", "書名")
          isbn = _import_row_isbn(row)
          source_raw = _import_row_value(row, "source", "Source", "來源")
          source_key = Book.import_source_key_from_label(source_raw)
          next if title.blank?
          eff = _import_book_batch_year_id_for_row(row, fallback)
          next if eff.nil? || eff < 1

          existing = _import_find_existing(row, title, isbn, source_key, eff)
          if existing
            @duplicates << { index: index, row: row, existing: existing }
          else
            @new_books << { index: index, row: row }
          end
        end
      else
        @imported_data.each_with_index do |row, index|
          @new_books << { index: index, row: row }
        end
      end

      @import_book_preview_ready =
        (@missing_columns.blank? &&
         has_title_column && has_isbn_column &&
         ((batch_year_id.present? && batch_year_id.to_i >= 1) || @duplicates.any? || @new_books.any?))
    end

    def _restore_import_preview(import_data, batch_year_id = nil)
      @imported_data = import_data
      @headers = import_data.first&.keys || []
      headers_stripped = @headers.map { |h| h&.to_s&.strip }
      normalized_headers = headers_stripped.map { |h| _normalize_book_csv_header_value(h) }.compact
      @missing_columns = @required_columns - normalized_headers
      @extra_columns = normalized_headers - @expected_columns

      @invalid_row_indices = []
      @imported_data.each_with_index do |row, index|
        @invalid_row_indices << index if _import_book_row_invalid?(row)
      end

      _rebuild_book_import_duplicate_preview!(batch_year_id)
      @batch_years = BatchYear.by_number_desc
    end
end
