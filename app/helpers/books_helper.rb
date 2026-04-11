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

  # Maps CSV/Excel column header to `edit_rows[row_index][...]` key; nil = read-only in preview.
  def import_header_semantic_key_for_edit(header)
    h = header.to_s.strip.delete("\uFEFF")
    return nil if status_column_in_import?(h)

    case h
    when "書名", "title", "Title" then "title"
    when "ISBN", "isbn", "國際標準書號" then "isbn"
    when "屆數", "batch_year" then "batch_year"
    when "屆數ID", "batch_year_id" then "batch_year_id"
    when "來源", "source", "Source" then "source"
    when "總數", "total", "Total" then "total"
    when "冊數", "volume", "Volume" then "volume"
    when "備註", "note", "Note" then "note"
    when "登錄號", "call_number" then "call_number"
    when "狀態", "status", "Status" then "status"
    else
      nil
    end
  end

  # First non-blank value for a row (same rules as BooksController / `Book.lookup_import_row_value`).
  def import_preview_row_value(row, *keys)
    Book.lookup_import_row_value(row, *keys)
  end

  # ISBN digits for preview (matches BooksController / spreadsheets with numeric ISBN cells).
  def import_preview_isbn_digits(row)
    Book.import_row_isbn_digits(row)
  end

  # True when this semantic field alone fails BooksController import rules (required / ISBN-13 / library 登錄號).
  def import_preview_book_field_invalid?(semantic, row)
    title = import_preview_row_value(row, "title", "Title", "書名")
    isbn_digits = import_preview_isbn_digits(row)
    source = import_preview_row_value(row, "source", "Source", "來源")
    source_key = Book.import_source_key_from_label(source)

    case semantic.to_s
    when "title" then title.blank?
    when "source"
      return true if source.blank?

      sk = Book.import_source_key_from_label(source)
      sk == "owned_by_teacher" && Book.import_teacher_user_from_source_label(source).nil?
    when "isbn" then isbn_digits.blank? || !Book.valid_isbn13?(isbn_digits)
    when "call_number"
      return false unless source_key == "owned_by_library"

      c = import_preview_row_value(row, "call_number", "登錄號").to_s.strip
      c.blank? || !c.match?(/\A\d{8}\z/)
    when "status"
      v = import_preview_row_value(row, "status", "狀態", "Status").to_s.strip
      v.present? && !VALID_BOOK_STATUSES.include?(v)
    when "batch_year_id"
      id_raw = import_preview_row_value(row, "batch_year_id", "屆數ID", "Batch_year_id")
      id_raw.present? && !(id_raw.to_s.strip.to_i.positive? && BatchYear.exists?(id: id_raw.to_s.strip.to_i))
    when "batch_year"
      lab = import_preview_row_value(row, "屆數", "batch_year", "Batch_year")
      lab.present? && BatchYear.find_id_from_import_label(lab).blank?
    else
      false
    end
  end

  # Simple ISBN display: normalize to digits only (auto-delete all dashes/spaces/symbols).
  def format_isbn13(isbn)
    isbn.to_s.gsub(/\D/, "")
  end
end
