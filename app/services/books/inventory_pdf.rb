# frozen_string_literal: true

require "prawn"
require "prawn/table"

module Books
  class InventoryPdf
    FONT_PATH = Rails.root.join("vendor/fonts/NotoSansTC-Regular.otf")

    def self.render(books, batch_year:, show_source_column:, source_title_suffix:)
      new(books, batch_year, show_source_column, source_title_suffix).render
    end

    def initialize(books, batch_year, show_source_column, source_title_suffix)
      @books = books
      @batch_year = batch_year
      @show_source_column = show_source_column
      @source_title_suffix = source_title_suffix
    end

    def render
      Prawn::Document.new(page_size: "A4", margin: 36) do |pdf|
        register_font(pdf)
        title = "第 #{@batch_year.batch_number} 屆書籍盤點表（來源：#{@source_title_suffix}）"
        pdf.text title, size: 14, align: :center
        pdf.move_down 20

        if @books.empty?
          pdf.text "（無書籍資料）", size: 10
        else
          data = build_table_data
          table_width = pdf.bounds.width
          pdf.table(data, header: true, width: table_width) do
            cells.style(size: 9, padding: [ 5, 6 ], valign: :center)
            row(0).background_color = "EEEEEE"
            cells.border_width = 0.5
            column(0).style(overflow: :shrink_to_fit, min_font_size: 7)
          end
        end
      end.render
    end

    private

    def register_font(pdf)
      unless FONT_PATH.exist?
        pdf.font "Helvetica"
        return
      end

      pdf.font_families.update("NotoSansTC" => { normal: FONT_PATH.to_s, bold: FONT_PATH.to_s })
      pdf.font "NotoSansTC"
    end

    def build_table_data
      headers = [ "書名", "ISBN", "總數" ]
      headers << "來源" if @show_source_column
      rows = @books.map do |book|
        row = [
          book.title.to_s,
          book.isbn.to_s.gsub(/\D/, ""),
          book.total.to_s
        ]
        if @show_source_column
          if book.source.to_s == "owned_by_teacher"
            teacher_name = book.user&.name.to_s.strip
            row << (teacher_name.present? ? "#{teacher_name}老師的書" : I18n.t("activerecord.enums.book.source.owned_by_teacher"))
          else
            row << I18n.t("activerecord.enums.book.source.#{book.source}")
          end
        end
        row
      end
      [ headers ] + rows
    end
  end
end
