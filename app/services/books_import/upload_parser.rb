# frozen_string_literal: true

module BooksImport
  # Parses a multipart books import upload: plain-text CSV (with encoding detection) or Excel (.xlsx/.xls) via Roo.
  # Returns [ headers, rows ] matching the shape of the previous BooksController helpers (row hashes keyed by header strings).
  class UploadParser
    XLS_OLE_MAGIC = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b.freeze

    def self.call(uploaded_file)
      new(uploaded_file).call
    end

    def initialize(uploaded_file)
      @uploaded_file = uploaded_file
    end

    def call
      raw = @uploaded_file.read
      raw = raw.force_encoding(Encoding::BINARY) if raw.encoding == Encoding::ASCII_8BIT
      case file_kind(raw)
      when :spreadsheet
        spreadsheet_rows(raw)
      when :csv
        content = decode_csv_text_to_utf8(raw)
        parse_csv(content)
      end
    end

    private

    def file_kind(raw_bytes)
      name = @uploaded_file.original_filename.to_s.downcase
      return :spreadsheet if name.end_with?(".xlsx", ".xls")
      return :spreadsheet if raw_bytes.bytesize >= 4 && raw_bytes.byteslice(0, 4) == "PK\x03\x04".b
      return :spreadsheet if raw_bytes.bytesize >= 8 && raw_bytes.byteslice(0, 8) == XLS_OLE_MAGIC

      :csv
    end

    def spreadsheet_extension(raw_bytes)
      name = @uploaded_file.original_filename.to_s.downcase
      return :xlsx if name.end_with?(".xlsx")
      return :xls if name.end_with?(".xls")
      return :xlsx if raw_bytes.bytesize >= 4 && raw_bytes.byteslice(0, 4) == "PK\x03\x04".b
      return :xls if raw_bytes.bytesize >= 8 && raw_bytes.byteslice(0, 8) == XLS_OLE_MAGIC

      :xlsx
    end

    def spreadsheet_rows(raw_bytes)
      require "roo"
      ext = spreadsheet_extension(raw_bytes)
      require "roo-xls" if ext == :xls

      path = @uploaded_file.tempfile.path
      spreadsheet = Roo::Spreadsheet.open(path, extension: ext)
      sheet = spreadsheet.sheet(0)
      first_row = sheet.first_row
      last_row = sheet.last_row
      return [ [], [] ] if first_row.nil? || last_row.nil? || first_row > last_row

      headers = sheet.row(first_row).map { |cell| cell.to_s.strip }
      rows = []
      ((first_row + 1)..last_row).each do |r|
        row_vals = sheet.row(r)
        row_hash = {}
        headers.each_with_index { |h, i| row_hash[h] = row_vals[i] }
        rows << row_hash
      end
      [ headers, rows ]
    end

    def decode_csv_text_to_utf8(raw)
      raw = raw.dup.force_encoding(Encoding::BINARY)
      strip_bom = ->(s) { s.delete_prefix("\uFEFF") }

      utf8 = raw.dup.force_encoding("UTF-8")
      return strip_bom.call(utf8.encode("UTF-8")) if utf8.valid_encoding?

      if raw.bytesize >= 2 && raw.byteslice(0, 2) == "\xFF\xFE".b
        decoded = raw.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        return strip_bom.call(decoded)
      end
      if raw.bytesize >= 2 && raw.byteslice(0, 2) == "\xFE\xFF".b
        decoded = raw.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        return strip_bom.call(decoded)
      end

      %w[CP950 Big5].each do |enc|
        begin
          decoded = raw.force_encoding(enc).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          return strip_bom.call(decoded)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          next
        end
      end

      %w[UTF-16LE UTF-16BE].each do |enc|
        begin
          decoded = raw.force_encoding(enc).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          return strip_bom.call(decoded)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          next
        end
      end

      strip_bom.call(raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: ""))
    end

    def parse_csv(content)
      lines = content.split(/\r?\n/)
      return [ [], [] ] if lines.empty?
      headers = parse_csv_line(lines[0])
      rows = lines[1..].filter_map do |line|
        next nil if line.strip.empty?
        values = parse_csv_line(line)
        headers.each_with_index.to_h { |h, i| [ h, values[i] ] }
      end
      [ headers, rows ]
    end

    def parse_csv_line(line)
      fields = []
      i = 0
      while i < line.length
        if line[i] == '"'
          i += 1
          field = +""
          while i < line.length
            if line[i] == '"'
              if line[i + 1] == '"'
                field << '"'
                i += 2
              else
                i += 1
                break
              end
            else
              field << line[i]
              i += 1
            end
          end
          fields << field
        else
          end_idx = line.index(",", i) || line.length
          fields << line[i...end_idx].to_s.strip
          i = end_idx + 1
        end
      end
      fields
    end
  end
end
