# frozen_string_literal: true

module BooksHelper
  # Query params for `/books/export` so CSV matches the current list (same filters + sort as `/books`).
  # Call only from `books/index` where @filter_* / @list_sort are set.
  def books_export_filter_params
    {
      batch_year_id: @filter_batch_year_id,
      q: @filter_q,
      source: @filter_source,
      status: @filter_status,
      sort: @list_sort
    }.compact_blank
  end

  # Import preview: if this column is a status column and the value is not in the valid options (including "—", blank, or a dash), show "不符合"
  VALID_BOOK_STATUSES = [ Book::STATUS_ON_SHELF, Book::STATUS_BORROWED, Book::STATUS_MISSING, Book::STATUS_RETURNED_LIBRARY ].freeze
  INVALID_STATUS_PLACEHOLDERS = [ "", "—", "－", "-", "–" ].freeze # Blank, full-width/half-width dashes

  def import_cell_display(header, value)
    return value unless status_column_in_import?(header)
    v = value.to_s.strip
    return "不符合" if v.blank? || INVALID_STATUS_PLACEHOLDERS.include?(v)
    VALID_BOOK_STATUSES.include?(v) ? value : "不符合"
  end

  def status_column_in_import?(header)
    h = header.to_s.strip.delete("\uFEFF") # Remove BOM
    h.downcase == "status" || h == "狀態" || h.include?("狀態")
  end

  # Simple ISBN display: normalize to digits only (auto-delete all dashes/spaces/symbols).
  def format_isbn13(isbn)
    isbn.to_s.gsub(/\D/, "")
  end
end
