class DashboardController < ApplicationController
  def index
    @library_books_on_shelf = Book.where(source: :owned_by_library, status: Book::STATUS_ON_SHELF).where.not(title: [ nil, "" ]).includes(:batch_year).order(:title)
    @library_books_borrowed = Book.where(source: :owned_by_library, status: Book::STATUS_BORROWED).where.not(title: [ nil, "" ]).includes(:batch_year, :user).order(:title)
    @users = User.active.order(:name)
  end
end
