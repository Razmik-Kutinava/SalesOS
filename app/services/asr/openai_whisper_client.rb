# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Asr
  # Облачный ASR: OpenAI Audio Transcriptions API (`whisper-1`).
  # Лимит ~25 МБ на файл; форматы: webm, wav, mp3, … — см. доку OpenAI.
  # Обзор для разработчиков: https://platform.openai.com/docs/guides/speech-to-text
  class OpenaiWhisperClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ApiError < Error
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    API_URL = "https://api.openai.com/v1/audio/transcriptions"

    class << self
      def transcribe(file_path)
        key = ENV.fetch("OPENAI_API_KEY", "").to_s.strip
        raise ConfigurationError, "Задайте OPENAI_API_KEY для ASR_BACKEND=openai." if key.blank?

        model = ENV.fetch("OPENAI_WHISPER_MODEL", "whisper-1")
        uri = URI.parse(API_URL)

        File.open(file_path, "rb") do |io|
          req = Net::HTTP::Post.new(uri)
          req["Authorization"] = "Bearer #{key}"
          filename = File.basename(file_path)
          form = [
            [ "file", io, { filename: filename } ],
            [ "model", model ]
          ]
          lang = ENV["OPENAI_WHISPER_LANGUAGE"].to_s.strip
          form << [ "language", lang ] if lang.present?

          req.set_form(form, "multipart/form-data")

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: read_timeout, open_timeout: open_timeout) do |http|
            http.request(req)
          end

          return parse_success(res.body) if res.is_a?(Net::HTTPSuccess)

          code = res.code.to_i
          raise ApiError.new(friendly_openai_error(code, res.body), status: code, body: res.body)
        end
      end

      def read_timeout
        ENV.fetch("OPENAI_WHISPER_READ_TIMEOUT", "120").to_i
      end

      def open_timeout
        ENV.fetch("OPENAI_WHISPER_OPEN_TIMEOUT", "30").to_i
      end

      private

      def friendly_openai_error(code, body)
        snippet = body.to_s[0, 280].to_s.tr("\r\n", " ")
        case code
        when 429
          "OpenAI Whisper: лимит запросов (HTTP 429). Проверь квоту и биллинг на platform.openai.com. " \
            "Локально: ASR_BACKEND=local_whisper, WHISPER_BIN и WHISPER_MODEL — см. docs/integrations/LOCAL-WHISPER-SETUP.md"
        when 401
          "OpenAI Whisper: неверный или отозванный ключ (HTTP 401). Проверь OPENAI_API_KEY."
        when 402, 403
          "OpenAI Whisper: доступ запрещён (HTTP #{code}). Проверь биллинг и права ключа."
        when 400..499
          "OpenAI Whisper HTTP #{code}: #{snippet}"
        else
          "OpenAI Whisper HTTP #{code}: #{snippet}"
        end
      end

      def parse_success(body)
        data = JSON.parse(body.to_s)
        text = data["text"].to_s.strip
        raise ApiError.new("OpenAI: пустой text", body: body) if text.blank?

        text
      rescue JSON::ParserError
        raise ApiError.new("OpenAI: невалидный JSON", body: body)
      end
    end
  end
end
