class DashboardController < ApplicationController
  def index
    if params[:clear_pending].present?
      _clear_pending_session
      redirect_to root_path, status: :see_other
      return
    end
    @library_books_borrowed = Book.where(source: :owned_by_library, status: Book::STATUS_BORROWED).where.not(title: [ nil, "" ]).includes(:batch_year, :borrower).order(:title)
    if current_user_admin? || current_user.nil?
      @users = User.active.order(:admin, :name)
    end
    # 多本同 ISBN 時請選擇冊別
    pending_ids = session[:pending_book_ids].to_a
    if pending_ids.any?
      @pending_books = Book.where(id: pending_ids).includes(:batch_year, :borrower).order(:id)
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
      @users = User.active.order(:admin, :name)
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
      render json: { has_13_digits: false, check_digit_valid: false, book_exists: false }, status: :bad_request
      return
    end
    digits_only = isbn.gsub(/\D/, "")
    has_13_digits = digits_only.length == 13
    check_digit_valid = has_13_digits && Book.valid_isbn13?(isbn)
    book_exists = Book.where(source: :owned_by_library)
                      .where.not(status: Book::STATUS_RETURNED_LIBRARY)
                      .where.not(title: [ nil, "" ])
                      .to_a.any? { |b| Book.isbn_match?(b.isbn, isbn) }
    render json: { has_13_digits: has_13_digits, check_digit_valid: check_digit_valid, book_exists: book_exists }
  end

  def process_isbn
    isbn = params[:isbn].to_s.strip
    if isbn.blank?
      redirect_to root_path, alert: "請掃描或輸入 ISBN。", status: :see_other
      return
    end
    if current_user_admin? || (current_user.nil? && params[:action_type].present?)
      _process_isbn_admin(isbn)
    else
      _process_isbn_student(isbn)
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
    unless book&.owned_by_library?
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
    if doing_return && book.borrowers.first&.id != borrower.id
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

  def _process_isbn_admin(isbn)
    action = params[:action_type].to_s == "return" ? "return" : "checkout"
    status_filter = action == "checkout" ? Book::STATUS_ON_SHELF : Book::STATUS_BORROWED
    books = Book.where(source: :owned_by_library, status: status_filter)
                .where.not(status: Book::STATUS_RETURNED_LIBRARY)
                .where.not(title: [ nil, "" ])
                .includes(:batch_year, :borrower)
                .to_a.select { |b| Book.isbn_match?(b.isbn, isbn) }

    if books.empty?
      if action == "checkout"
        all_with_isbn = Book.where(source: :owned_by_library)
                            .where.not(status: Book::STATUS_RETURNED_LIBRARY)
                            .where.not(title: [ nil, "" ])
                            .to_a.select { |b| Book.isbn_match?(b.isbn, isbn) }
        alert_msg = all_with_isbn.any? ? "此書仍在借閱，請勿重複借閱。" : "找不到此書。"
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
      books = books.select { |b| b.borrowers.first&.id == borrower.id }
      if books.empty?
        redirect_to root_path, alert: "此書不是此人借閱的，無法歸還。", status: :see_other
        return
      end
    end

    # Checkout: if this ISBN has more than one volume (any status), always show volume picker
    all_volumes_with_isbn = if action == "checkout"
      Book.where(source: :owned_by_library)
          .where.not(status: Book::STATUS_RETURNED_LIBRARY)
          .where.not(title: [ nil, "" ])
          .to_a.select { |b| Book.isbn_match?(b.isbn, isbn) }
    else
      []
    end

    if action == "checkout" && all_volumes_with_isbn.size >= 2
      session[:pending_book_ids] = books.map(&:id)
      session[:pending_action] = action
      session[:pending_user_id] = borrower&.id
      session[:pending_isbn] = isbn
      redirect_to root_path, status: :see_other
      return
    end

    if books.size == 1
      _do_action(books.first, action, borrower)
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    session[:pending_book_ids] = books.map(&:id)
    session[:pending_action] = action
    session[:pending_user_id] = borrower&.id
    session[:pending_isbn] = isbn
    redirect_to root_path, status: :see_other
  end

  def _process_isbn_student(isbn)
    books = Book.where(source: :owned_by_library)
                .where.not(status: Book::STATUS_RETURNED_LIBRARY)
                .where.not(title: [ nil, "" ])
                .includes(:batch_year, :borrower)
                .to_a.select { |b| Book.isbn_match?(b.isbn, isbn) }

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
      if book.status == Book::STATUS_BORROWED && book.borrowers.first&.id != borrower.id
        redirect_to root_path, alert: "此書不是您借閱的，無法歸還。", status: :see_other
        return
      end
      _do_borrow_or_return_by_status(book, borrower)
      redirect_to root_path, notice: @process_notice, status: :see_other
      return
    end

    books = books.select do |b|
      (b.status == Book::STATUS_ON_SHELF && b.batch_year_id == borrower.batch_year_id) ||
        (b.status == Book::STATUS_BORROWED && b.borrowers.first&.id == borrower.id)
    end
    if books.empty?
      redirect_to root_path, alert: "沒有您可借或可還的書（此書與您的屆數不同或非您借閱）。", status: :see_other
      return
    end

    session[:pending_book_ids] = books.map(&:id)
    session[:pending_action] = nil
    session[:pending_user_id] = borrower.id
    session[:pending_isbn] = isbn
    redirect_to root_path, status: :see_other
  end

  def _do_action(book, action, borrower)
    if action == "checkout"
      book.update!(user_id: borrower.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
      book.circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
      @process_notice = "已登記借閱：#{book.title} → #{borrower.name}。"
    else
      book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
      book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
      @process_notice = "已還書：#{book.title}。"
    end
  end

  def _do_borrow_or_return_by_status(book, borrower)
    if book.status == Book::STATUS_ON_SHELF
      book.update!(user_id: borrower.id, status: Book::STATUS_BORROWED, borrowed_at: Time.current)
      book.circulation_records.create!(user_id: borrower.id, borrowed_at: Time.current)
      @process_notice = "已登記借閱：#{book.title} → #{borrower.name}。"
    else
      book.circulation_records.where(returned_at: nil).update_all(returned_at: Time.current)
      book.update!(user_id: nil, status: Book::STATUS_ON_SHELF, borrowed_at: nil)
      @process_notice = "已還書：#{book.title}。"
    end
  end

  def _student_at_borrow_limit?(borrower)
    return false if borrower.blank? || borrower.admin?
    CirculationRecord.where(user_id: borrower.id, returned_at: nil)
                     .joins(:book)
                     .where(books: { source: :owned_by_library, status: Book::STATUS_BORROWED })
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
