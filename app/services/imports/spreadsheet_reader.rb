# frozen_string_literal: true

require "roo"

module Imports
  # Чтение первой строки (заголовки) и всех строк данных из CSV / XLSX / XLS.
  class SpreadsheetReader
    class Error < StandardError; end

    def self.extension_for(filename)
      ext = File.extname(filename.to_s).delete(".").downcase
      return :csv if ext == "csv"
      return :xlsx if ext == "xlsx"
      return :xls if ext == "xls"

      raise Error, "Неподдерживаемый формат: .#{ext.presence || '?'}"
    end

    def self.open_path(path, extension)
      Roo::Spreadsheet.open(path.to_s, extension: extension)
    end

    # @return [Array<String>] первая строка как заголовки
    def self.headers_from_path(path, extension)
      sheet = open_path(path, extension).sheet(0)
      row1 = sheet.row(sheet.first_row)
      row1.map { |c| c.to_s.strip }
    end

    # @yield [Array<String> headers, Enumerator<Array>] rows 2..last (каждая строка — массив ячеек)
    def self.each_data_row(path, extension)
      x = open_path(path, extension).sheet(0)
      headers = x.row(x.first_row).map { |c| c.to_s.strip }
      fr = x.first_row
      lr = x.last_row
      return [ headers, [].enumerator ] if fr.nil? || lr.nil? || fr >= lr

      enum = Enumerator.new do |y|
        ((fr + 1)..lr).each do |r|
          y << x.row(r)
        end
      end
      [ headers, enum ]
    end
  end
end
