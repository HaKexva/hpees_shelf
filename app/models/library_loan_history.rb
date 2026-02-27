# frozen_string_literal: true

class LibraryLoanHistory < ApplicationRecord
  belongs_to :book, optional: true
  belongs_to :batch_year, optional: true

  validates :book_title, presence: true
  validates :returned_at, presence: true
end
