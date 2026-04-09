# frozen_string_literal: true

class PublicBorrowReturnController < DashboardController
  skip_before_action :require_login

  private

  def _borrow_return_home_path
    root_path
  end

  public

  # Public borrow/return page (students use id_number; no authentication required)
  def index
    # Reference list only; no user list exposed
    @library_books_borrowed = Book.where(status: Book::STATUS_BORROWED)
                                  .where.not(title: [ nil, "" ])
                                  .includes(:batch_year, :borrowers)
                                  .order(:title)
  end
end
