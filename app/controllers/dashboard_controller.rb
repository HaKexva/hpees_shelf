class DashboardController < ApplicationController
  def index
    if params[:clear_pending].present?
      _clear_pending_session
      redirect_to root_path, status: :see_other
      return
    end
    # 目前借閱中：顯示所有來源的書，只要狀態是「借閱中」且有書名
    @library_books_borrowed = Book.where(status: Book::STATUS_BORROWED)
                                  .where.not(title: [ nil, "" ])
                                  .includes(:batch_year, :borrowers)
                                  .order(:title)
    if current_user_admin? || current_user.nil?
      @users = User.active.order(:admin, :name)
    end
    # 多本同 ISBN 時請選擇冊別
    pending_ids = session[:pending_book_ids].to_a
    if pending_ids.any?
      @pending_books = Book.where(id: pending_ids).includes(:batch_year, :borrowers).order(:id)
      @pending_action = session[:pending_action]
      @pending_user_id = session[:pending_user_id]
      @pending_isbn_display = session[:pending_isbn]
    else
      @pending_books = nil
      @pending_action = nil
      @pending_user_id = nil
      @pending_isbn_display = nil
    end
  end

  def loan_history
    if current_user_admin? || current_user.nil?
      # Include all users (active, resigned, graduated) so admins can view anyone's loan history
      @users = User.includes(:batch_year).order(:admin, :name)
      filter_user_id = params[:user_id].presence&.to_i
      filter_user_id = current_user&.id if filter_user_id.blank? && current_user.present?
      if filter_user_id.present?
        @records = CirculationRecord.where(user_id: filter_user_id).includes(:book, :user).order(borrowed_at: :desc).limit(500)
        @filter_user_id = filter_user_id
      else
        @records = []
        @filter_user_id = nil
      end
    else
      @records = current_user.circulation_records.includes(:book).order(borrowed_at: :desc).limit(500)
    end
  end

  def validate_isbn
    isbn = params[:isbn].to_s.strip
    if isbn.blank?
      render json: { has_13_digits: false, check_digit_valid: false, book_exists: false, duplicates: [] }, status: :bad_request
      return
    end
    digits_only = isbn.gsub(/\D/, "")
    has_13_digits = digits_only.length == 13
    check_digit_valid = has_13_digits && Book.valid_isbn13?(isbn)
    # 借還系統看所有來源的書，只要不是「歸還圖書館」且有書名；每本都要檢查總數（含 circulation）
    matching_books =
      Book.where.not(status: Book::STATUS_RETURNED_LIBRARY)
          .where.not(title: [ nil, "" ])
          .includes(:batch_year, :user, :circulation_records)
          .to_a
          .select { |b| Book.isbn_match?(b.isbn, isbn) }
    book_exists = matching_books.any?
    # 直接查 DB 未還本數，確保總數 3 借出 1 本後仍顯示可借 2
    book_ids = matching_books.map(&:id)
    active_counts = CirculationRecord.where(book_id: book_ids, returned_at: nil).group(:book_id).count

    duplicates =
      matching_books.map do |b|
        source_label =
          if b.source.present?
            I18n.t("activerecord.enums.book.source.#{b.source}", default: b.source)
          else
            nil
          end
        if b.owned_by_teacher? && b.user.present?
          source_label = "#{source_label}（#{b.user.name}）"
        end
        eff_total = b.total.to_i.positive? ? b.total.to_i : 1
        active = active_counts[b.id].to_i
        avail = [ eff_total - active, 0 ].max
        borrowable_for_checkout =
          if b.owned_by_library? && eff_total > 1
            avail.positive?
          else
            b.status == Book::STATUS_ON_SHELF
          end
        {
          id: b.id,
          title: b.title,
          edition_part: b.edition_part,
          volume: b.volume,
          batch_label: b.batch_year&.display_label_with_grade,
          source_label: source_label,
          call_number: b.call_number,
          available_copies: avail,
          borrowable_for_checkout: borrowable_for_checkout
        }
      end
    render json: {
      has_13_digits: has_13_digits,
      check_digit_valid: check_digit_valid,
      book_exists: book_exists,
      duplicates: duplicates
    }
  end

  def process_isbn
    isbn = params[:isbn].to_s.strip
    if isbn.blank?
      redirect_to root_path, alert: "請掃描或輸入 ISBN。", status: :see_other
      return
    end

    pending_book_id = params[:pending_book_id].presence&.to_i

    if current_user_admin? || (current_user.nil? && params[:action_type].present?)
      _process_isbn_admin(isbn, pending_book_id: pending_book_id)
    else
      _process_isbn_student(isbn, pending_book_id: pending_book_id)
    end
  end

  def confirm_borrow_return
    book_id = params[:book_id].presence&.to_i
    pending_ids = session[:pending_book_ids].to_a
    unless book_id && pending_ids.include?(book_id)
      _clear_pending_session
      redirect_to root_path, alert: "請選擇冊別。", status: :see_other
      return
    end

    book = Book.find_by(id: book_id)
    unless book
      _clear_pending_session
      redirect_to root_path, alert: "找不到該書籍。", status: :see_other
      return
    end

    action = session[:pending_action].to_s
    borrower = User.find_by(id: session[:pending_user_id]) if session[:pending_user_id].present?
    borrower ||= current_user

    need_borrower = action == "checkout" || (action.blank? && book.status == Book::STATUS_ON_SHELF)
    if need_borrower && borrower.blank?
      _clear_pending_session
      redirect_to root_path, status: :see_other
      return
    end

    if need_borrower && _student_at_borrow_limit?(borrower)
      _clear_pending_session
      redirect_to root_path, alert: "學生一次只能借一本書，請先歸還再借。", status: :see_other
      return
    end

    doing_return = action == "return" || (action.blank? && book.status == Book::STATUS_BORROWED)
    if doing_return && !book.borrowed_by?(borrower)
      _clear_pending_session
      redirect_to root_path, alert: "此書不是此人借閱的，無法歸還。", status: :see_other
      return
    end

    doing_checkout = action == "checkout" || (action.blank? && book.status == Book::STATUS_ON_SHELF)
    if doing_checkout && book.status != Book::STATUS_ON_SHELF
      _clear_pending_session
      redirect_to root_path, alert: "此書已借閱中，請勿重複借閱。", status: :see_other
      return
    end
    if doing_checkout && !borrower.admin? && book.batch_year_id != borrower.batch_year_id
      _clear_pending_session
      redirect_to root_path, alert: "此書與借閱人的屆數不同，無法借閱。", status: :see_other
      return
    end

    if action == "return" || action == "checkout"
      _do_action(book, action, borrower)
    else
      _do_borrow_or_return_by_status(book, borrower)
    end
    _clear_pending_session
    redirect_to root_path, notice: @process_notice, status: :see_other
  end

  private

  def _process_isbn_admin(isbn, pending_book_id: nil)
    action = params[:action_type].to_s == "return" ? "return" : "checkout"
    base_books =
      Book.where.not(status: Book::STATUS_RETURNED_LIBRARY)
          .where.not(title: [ nil, "" ])
          .includes(:batch_year, :borrowers, :circulation_records)
          .to_a
          .select { |b| Book.isbn_match?(b.isbn, isbn) }

    # 總數 > 1 的書：借出 1 本後其餘仍可借（用 DB 查未還本數）
    active_counts = CirculationRecord.where(book_id: base_books.map(&:id), returned_at: nil).group(:book_id).count
    books =
      if action == "checkout"
        base_books.select do |b|
          eff_total = b.total.to_i.positive? ? b.total.to_i : 1
          if b.owned_by_library? && eff_total > 1
            (eff_total - active_counts[b.id].to_i).positive?
          else
            b.status == Book::STATUS_ON_SHELF
          end
        end
      else
        base_books.select { |b| b.status == Book::STATUS_BORROWED }
      end

    if pending_book_id.present?
      books = books.select { |b| b.id == pending_book_id }
    end

    if books.empty?
      if action == "checkout"
        alert_msg =
          if base_books.any?
            "此本目前無可借，請在表單中改選其他冊別。"
          else
            "找不到此書。"
          end
      else
        alert_msg = "找不到可還的書（借閱中且符合此 ISBN）。"
      end
      redirect_to root_path, alert: alert_msg, status: :see_other
      return
    end

    user_id = params[:user_id].presence&.to_i
    id_number = params[:id_number].to_s.strip
    borrower = if user_id.present?
      User.find_by(id: user_id)
    elsif id_number.present?
      User.active.find_by(id_number: id_number)
    else
      current_user
    end

    if action == "checkout" && borrower.blank?
      redirect_to root_path, alert: id_number.present? ? "找不到此學號的學生。" : "找不到借閱人。", status: :see_other
      return
    end

    if action == "checkout" && _student_at_borrow_limit?(borrower)
      redirect_to root_path, alert: "學生一次只能借一本書，請先歸還再借。", status: :see_other
      return
    end

    if action == "checkout" && !borrower.admin?
      books = books.select { |b| b.batch_year_id == borrower.batch_year_id }
      if books.empty?
        redirect_to root_path, alert: "此書與借閱人的屆數不同，無法借閱。", status: :see_other
        return
      end
    end

    if action == "return"
      books = books.select { |b| b.borrowed_by?(borrower) }
      if books.empty?
        redirect_to root_path, alert: "此書不是此人借閱的，無法歸還。", status: :see_other
        return
      end
    end

    if books.size == 1
      _do_action(books.first, action, borrower)
      _clear_pending_session
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    keys = books.map { |b| _duplicate_display_key(b) }.uniq
    if keys.size == 1
      _do_action(books.first, action, borrower)
      _clear_pending_session
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    # 只做「送出前」選冊別，不再導向「送出後」的選冊別畫面
    _clear_pending_session
    redirect_to root_path, alert: "有多本相同 ISBN，請在表單中選擇冊別後再送出。", status: :see_other
  end

  def _process_isbn_student(isbn, pending_book_id: nil)
    # 學生借還：同樣看所有來源；總數 > 1 的書借出 1 本後其餘仍可借
    books = Book.where.not(status: Book::STATUS_RETURNED_LIBRARY)
                .where.not(title: [ nil, "" ])
                .includes(:batch_year, :borrowers, :circulation_records)
                .to_a
                .select { |b| Book.isbn_match?(b.isbn, isbn) }

    if pending_book_id.present?
      books = books.select { |b| b.id == pending_book_id }
    end

    if books.empty?
      redirect_to root_path, alert: "找不到此 ISBN 的圖書館館藏（ISBN：#{isbn}）。", status: :see_other
      return
    end

    borrower = current_user
    if borrower.blank?
      redirect_to root_path, status: :see_other
      return
    end

    if books.size == 1
      book = books.first
      if book.status == Book::STATUS_ON_SHELF && _student_at_borrow_limit?(borrower)
        redirect_to root_path, alert: "學生一次只能借一本書，請先歸還再借。", status: :see_other
        return
      end
      if book.status == Book::STATUS_ON_SHELF && book.batch_year_id != borrower.batch_year_id
        redirect_to root_path, alert: "此書與您的屆數不同，無法借閱。", status: :see_other
        return
      end
      if book.status == Book::STATUS_BORROWED && !book.borrowed_by?(borrower)
        redirect_to root_path, alert: "此書不是您借閱的，無法歸還。", status: :see_other
        return
      end
      _do_borrow_or_return_by_status(book, borrower)
      _clear_pending_session
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    books = books.select do |b|
      (b.status == Book::STATUS_ON_SHELF && b.batch_year_id == borrower.batch_year_id) ||
        (b.status == Book::STATUS_BORROWED && b.borrowed_by?(borrower))
    end
    if books.empty?
      redirect_to root_path, alert: "沒有您可借或可還的書（此書與您的屆數不同或非您借閱）。", status: :see_other
      return
    end

    if books.size == 1
      _do_borrow_or_return_by_status(books.first, borrower)
      _clear_pending_session
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    keys = books.map { |b| _duplicate_display_key(b) }.uniq
    if keys.size == 1
      _do_borrow_or_return_by_status(books.first, borrower)
      _clear_pending_session
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    # 只做「送出前」選冊別，不再導向「送出後」的選冊別畫面
    _clear_pending_session
    redirect_to root_path, alert: "有多本相同 ISBN，請在表單中選擇冊別後再送出。", status: :see_other
  end

  def _do_action(book, action, borrower)
    if action == "checkout"
      if book.owned_by_library? && book.effective_total > 1
        if book.can_borrow_copy?
          book.circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
          book.update!(status: Book::STATUS_BORROWED, borrowed_at: Time.current)
        else
          raise ActiveRecord::RecordInvalid, "no copies available"
        end
      else
        book.update!(user_id: borrower.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
        book.circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
      end
      @process_notice = "已登記借閱：#{book.title} → #{borrower.name}。"
    else
      if book.owned_by_library? && book.effective_total > 1
        rec = book.circulation_records.where(user_id: borrower.id, returned_at: nil).order(:borrowed_at).first
        if rec
          rec.update!(returned_at: Time.current)
          if book.active_circulation_records.exists?
            # 仍有其他人借閱，維持「借閱中」狀態
          else
            book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
          end
        end
      else
        book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
        book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
      end
      @process_notice = "已還書：#{book.title}。"
    end
  end

  def _do_borrow_or_return_by_status(book, borrower)
    if book.status == Book::STATUS_ON_SHELF
      if book.owned_by_library? && book.effective_total > 1
        if book.can_borrow_copy?
          book.circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
          book.update!(status: Book::STATUS_BORROWED, borrowed_at: Time.current)
        else
          raise ActiveRecord::RecordInvalid, "no copies available"
        end
      else
        book.update!(user_id: borrower.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
        book.circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
      end
      @process_notice = "已登記借閱：#{book.title} → #{borrower.name}。"
    else
      if book.owned_by_library? && book.effective_total > 1
        rec = book.circulation_records.where(user_id: borrower.id, returned_at: nil).order(:borrowed_at).first
        if rec
          rec.update!(returned_at: Time.current)
          if book.active_circulation_records.exists?
            # 仍有其他人借閱，維持「借閱中」狀態
          else
            book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
          end
        end
      else
        book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
        book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
      end
      @process_notice = "已還書：#{book.title}。"
    end
  end

  def _duplicate_display_key(book)
    [
      book.batch_year_id,
      book.source,
      book.user_id,
      book.call_number,
      book.volume,
      book.edition_part
    ]
  end

  def _student_at_borrow_limit?(borrower)
    return false if borrower.blank? || borrower.admin?
    # 借閱上限：學生一次只能借一本「任何來源」且尚未歸還的書
    CirculationRecord.where(user_id: borrower.id, returned_at: nil)
                     .joins(:book)
                     .where(books: { status: Book::STATUS_BORROWED })
                     .exists?
  end

  def _clear_pending_session
    session.delete(:pending_book_ids)
    session.delete(:pending_action)
    session.delete(:pending_mode)
    session.delete(:pending_user_id)
    session.delete(:pending_isbn)
  end
end
