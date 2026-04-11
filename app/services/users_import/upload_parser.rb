# frozen_string_literal: true

module UsersImport
  # Parses a multipart users import upload: plain-text CSV (with encoding detection) or Excel (.xlsx/.xls) via Roo.
  # Returns [ headers, rows ] with row hashes keyed by header strings (same shape as legacy UsersController CSV parsing).
  class UploadParser
    XLS_OLE_MAGIC = "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b.freeze

    def self.call(uploaded_file, expected_columns: %w[name])
      new(uploaded_file, expected_columns: expected_columns).call
    end

    def initialize(uploaded_file, expected_columns:)
      @uploaded_file = uploaded_file
      @expected_columns = expected_columns
    end

    def call
      raw = @uploaded_file.read
      raw = raw.force_encoding(Encoding::BINARY) if raw.encoding == Encoding::ASCII_8BIT
      case file_kind(raw)
      when :spreadsheet
        spreadsheet_rows(raw)
      when :csv
        content = decode_csv_to_utf8(raw)
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

    def normalize_header(value)
      s = value.to_s.strip
      return nil if s.blank?

      case s
      when "姓名" then "name"
      when "學號" then "id_number"
      when "座號" then "seat_number"
      when "屆數ID" then "batch_year_id"
      when "屆數" then "batch_year"
      when "電子信箱" then "email"
      when "管理員" then "admin"
      else s.downcase.presence
      end
    end

    # Try decoding CSV bytes into UTF-8 (Excel Big5 / Google Sheets UTF-8 BOM / UTF-16, etc.).
    def decode_csv_to_utf8(raw)
      expected = @expected_columns || %w[name]
      strip_bom = ->(s) { s.delete_prefix("\uFEFF") }

      header_matches_expected = lambda do |decoded|
        header_line = decoded.lines.first.to_s
        headers = parse_csv_line(header_line)
        normalized_headers = headers.map { |h| normalize_header(h) }.compact
        (expected - normalized_headers).empty?
      end

      utf8 = raw.dup.force_encoding("UTF-8")
      if utf8.valid_encoding?
        decoded = strip_bom.call(utf8.encode("UTF-8"))
        return decoded if header_matches_expected.call(decoded)
      end

      [
        -> { raw.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("UTF-16BE").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("CP950").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") },
        -> { raw.force_encoding("Big5").encode("UTF-8", invalid: :replace, undef: :replace, replace: "") }
      ].each do |decoder|
        begin
          decoded = strip_bom.call(decoder.call)
          return decoded if header_matches_expected.call(decoded)
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
