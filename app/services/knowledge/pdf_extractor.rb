# frozen_string_literal: true

require "pdf/reader"

module Knowledge
  class PdfExtractor
    class Error < StandardError; end

    def self.call(io)
      reader = PDF::Reader.new(io)
      text = reader.pages.map { |p| p.text.to_s }.join("\n\n").strip
      raise Error, "В PDF не удалось извлечь текст (пусто или скан без OCR)." if text.blank?

      text
    rescue PDF::Reader::MalformedPDFError => e
      raise Error, "Некорректный PDF: #{e.message}"
    end
  end
end
