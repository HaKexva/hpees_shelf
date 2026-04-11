# frozen_string_literal: true

module BooksHelper
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
    when "來源", "source", "Source" then "source"
    when "總數", "total", "Total" then "total"
    when "冊數", "volume", "Volume" then "volume"
    when "備註", "note", "Note" then "note"
    when "登錄號", "call_number" then "call_number"
    else
      nil
    end
  end

  # First non-blank value for a row (same key order as BooksController import parsing).
  def import_preview_row_value(row, *keys)
    keys.each do |k|
      v = row[k]
      next if v.blank?

      s = v.to_s.strip
      return s if s.present?
    end
    nil
  end

  # ISBN digits for preview (matches BooksController / spreadsheets with numeric ISBN cells).
  def import_preview_isbn_digits(row)
    raw = nil
    %w[isbn ISBN 國際標準書號].each do |k|
      v = row[k]
      next if v.blank?

      raw = v
      break
    end
    Book.import_isbn_digits(raw)
  end

  # True when this semantic field alone fails BooksController import rules (required / ISBN-13 / library 登錄號).
  def import_preview_book_field_invalid?(semantic, row)
    title = import_preview_row_value(row, "title", "Title", "書名")
    isbn_digits = import_preview_isbn_digits(row)
    source = import_preview_row_value(row, "source", "Source", "來源")
    source_key = Book.import_source_key_from_label(source)

    case semantic.to_s
    when "title" then title.blank?
    when "source" then source.blank?
    when "isbn" then isbn_digits.blank? || !Book.valid_isbn13?(isbn_digits)
    when "call_number"
      return false unless source_key == "owned_by_library"

      c = import_preview_row_value(row, "call_number", "登錄號").to_s.strip
      c.blank? || !c.match?(/\A\d{8}\z/)
    else
      false
    end
  end

  # Simple ISBN display: normalize to digits only (auto-delete all dashes/spaces/symbols).
  def format_isbn13(isbn)
    isbn.to_s.gsub(/\D/, "")
  end
end
