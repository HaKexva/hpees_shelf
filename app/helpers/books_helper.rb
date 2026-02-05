# frozen_string_literal: true

module BooksHelper
  # 標籤圖示（小 tag icon）
  TAG_ICON_SVG = <<~SVG.strip.freeze
    <svg class="w-3.5 h-3.5 shrink-0" fill="currentColor" viewBox="0 0 20 20" aria-hidden="true"><path fill-rule="evenodd" d="M5 2a1 1 0 0 0-.707.293l-2 2a1 1 0 0 0 0 1.414l8 8a1 1 0 0 0 1.414 0l6-6A1 1 0 0 0 19 7V3a1 1 0 0 0-1-1H5zm2 3a1 1 0 1 0 0 2 1 1 0 0 0 0-2z" clip-rule="evenodd"/></svg>
  SVG

  def book_tag_badge(text, selected: false)
    return "" if text.blank?
    content = safe_join([ TAG_ICON_SVG.html_safe, content_tag(:span, text) ], " ")
    content_tag(:span, content, class: "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium #{selected ? 'bg-blue-100 text-blue-800 ring-1 ring-blue-600' : 'bg-gray-100 text-gray-700'}")
  end

  # 匯入預覽時：若該欄為狀態且值不在選項內（含 "—"、空白、破折號），顯示「不符合」
  VALID_BOOK_STATUSES = [ Book::STATUS_ON_SHELF, Book::STATUS_BORROWED, Book::STATUS_MISSING, Book::STATUS_RETURNED_LIBRARY ].freeze
  INVALID_STATUS_PLACEHOLDERS = [ "", "—", "－", "-", "–" ].freeze # 空白、全形/半形破折號

  def import_cell_display(header, value)
    return value unless status_column_in_import?(header)
    v = value.to_s.strip
    return "不符合" if v.blank? || INVALID_STATUS_PLACEHOLDERS.include?(v)
    VALID_BOOK_STATUSES.include?(v) ? value : "不符合"
  end

  def status_column_in_import?(header)
    h = header.to_s.strip.delete("\uFEFF") # 移除 BOM
    h.downcase == "status" || h == "狀態" || h.include?("狀態")
  end

  # 老師的書：從 book.tag 反推應選的管理員姓名（供 dropdown 預選）
  def selected_teacher_name_for_book(book, admin_users)
    return "" unless book&.teacher_tag? && book.tag.present?
    tag = book.tag.to_s
    admin_users.find { |u| Book.tag_from_teacher_name(u.name) == tag }&.name.to_s
  end
end
