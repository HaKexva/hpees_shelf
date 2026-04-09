# WickedPDF Global Configuration
#
# Use this to set up shared configuration options for your entire application.
# Any of the configuration options shown here can also be applied to single
# models by passing arguments to the `render :pdf` call.
#
# To learn more, check out the README:
#
# https://github.com/mileszs/wicked_pdf/blob/master/README.md

require "wicked_pdf"

WickedPdf.configure do |config|
  # wkhtmltopdf must be available on PATH, or set via WKHTMLTOPDF_PATH.
  #
  # NOTE: `wkhtmltopdf-binary` does not provide an Apple Silicon (arm64) macOS
  # binary. On arm64-darwin you should install wkhtmltopdf separately (often
  # via Homebrew/cask, running under Rosetta if needed) and point this to it.
  env_path = ENV["WKHTMLTOPDF_PATH"].to_s.strip
  if env_path.present?
    config.exe_path = env_path
  else
    path_entries = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
    found = path_entries.filter_map do |dir|
      p = File.join(dir, "wkhtmltopdf")
      File.exist?(p) && File.executable?(p) ? p : nil
    end.first

    # On Apple Silicon, it's common for `wkhtmltopdf` on PATH to be the
    # `wkhtmltopdf-binary` gem wrapper which fails with EBADARCH. In that case
    # require an explicit WKHTMLTOPDF_PATH (or a real system install).
    if RUBY_PLATFORM.include?("arm64-darwin") && found.to_s.include?("/.gem/")
      found = nil
    end

    if found.present?
      config.exe_path = found
    elsif !RUBY_PLATFORM.include?("arm64-darwin")
      begin
        config.exe_path = Gem.bin_path("wkhtmltopdf-binary", "wkhtmltopdf")
      rescue StandardError
        # Leave nil: request specs will skip if wkhtmltopdf isn't available.
      end
    end
  end

  # Needed for wkhtmltopdf 0.12.6+ to use many wicked_pdf asset helpers
  # config.enable_local_file_access = true

  # Layout file to be used for all PDFs
  # (but can be overridden in `render :pdf` calls)
  # config.layout = 'pdf.html'

  # Using wkhtmltopdf without an X server can be achieved by enabling the
  # 'use_xvfb' flag. This will wrap all wkhtmltopdf commands around the
  # 'xvfb-run' command, in order to simulate an X server.
  #
  # config.use_xvfb = true
end
