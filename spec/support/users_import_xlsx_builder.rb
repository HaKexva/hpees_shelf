# frozen_string_literal: true

# Builds a minimal users_import.xlsx with a 屆數ID column (numeric) for request specs.
module UsersImportXlsxBuilder
  module_function

  def build(batch_year_id:)
    src = Rails.root.join("spec/fixtures/files/users_import.xlsx")
    Dir.mktmpdir do |dir|
      raise "unzip failed" unless system("unzip", "-q", src.to_s, "-d", dir)

      ss_path = File.join(dir, "xl/sharedStrings.xml")
      ss = File.read(ss_path)
      ss.sub!('count="6" uniqueCount="6"', 'count="7" uniqueCount="7"')
      ss.sub!("</sst>", '<si><t>屆數ID</t></si></sst>')
      File.write(ss_path, ss)

      sh_path = File.join(dir, "xl/worksheets/sheet1.xml")
      sh = File.read(sh_path)
      sh.sub!(
        '<c r="C1" t="s"><v>2</v></c>',
        '<c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>6</v></c>'
      )
      sh.sub!(
        '<c r="C2" t="s"><v>5</v></c>',
        "<c r=\"C2\" t=\"s\"><v>5</v></c><c r=\"D2\"><v>#{batch_year_id.to_i}</v></c>"
      )
      File.write(sh_path, sh)

      out_abs = File.join(Dir.tmpdir, "users_import_test_#{Process.pid}_#{batch_year_id}.xlsx")
      Dir.chdir(dir) { raise "zip failed" unless system("zip", "-q", "-r", out_abs, ".") }

      data = File.binread(out_abs)
      File.delete(out_abs) if File.exist?(out_abs)
      data
    end
  end
end
