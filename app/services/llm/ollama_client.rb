# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Llm
  # HTTP-клиент к Ollama API (без streaming). См. docs/integrations/OLLAMA-RAILS-INTEGRATION.md
  class OllamaClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class HttpError < Error
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end
    class TimeoutError < Error; end

    Configuration = Data.define(:base_url, :default_model, :open_timeout, :read_timeout) do
      def self.from_env
        base = ENV.fetch("OLLAMA_HOST", "http://127.0.0.1:11434").to_s.strip.chomp("/")
        raise ConfigurationError, "OLLAMA_HOST is blank" if base.empty?

        model = ENV.fetch("OLLAMA_MODEL", "llama3.2").to_s.strip
        model = "llama3.2" if model.blank?

        new(
          base_url: base,
          default_model: model,
          open_timeout: ENV.fetch("OLLAMA_OPEN_TIMEOUT", "5").to_i,
          read_timeout: ENV.fetch("OLLAMA_READ_TIMEOUT", "120").to_i
        )
      end
    end

    def initialize(config = nil)
      @config = config || Configuration.from_env
    end

    attr_reader :config

    # messages: [{ "role" => "user"|"system"|"assistant", "content" => "..." }]
    # format: "json" для structured output (если модель поддерживает)
    # options: хеш для Ollama (temperature, num_predict, top_p и т.д.) — см. POST /api/chat
    def chat(messages:, model: nil, format: nil, options: nil)
      raise ArgumentError, "messages must be non-empty" if messages.blank?

      body = {
        model: model.presence || config.default_model,
        messages: messages,
        stream: false
      }
      body[:format] = format if format.present?
      body[:options] = options if options.present?

      post_json("/api/chat", body)
    end

    # Извлекает текст ответа ассистента из ответа /api/chat
    def self.message_content(response_hash)
      response_hash.dig("message", "content")
    end

    # GET /api/tags — список локальных моделей (для health-check)
    def tags
      get_json("/api/tags")
    end

    # POST /api/embeddings — см. docs/integrations/OLLAMA-RAILS-INTEGRATION.md
    # Возвращает хэш с ключом "embedding" => [Float, ...]
    def embed(prompt:, model: nil)
      raise ArgumentError, "prompt must be non-empty" if prompt.to_s.blank?

      m = model.presence || ENV.fetch("OLLAMA_EMBED_MODEL", "nomic-embed-text").to_s.strip
      m = "nomic-embed-text" if m.blank?

      body = { model: m, prompt: prompt.to_s }
      post_json("/api/embeddings", body)
    end

    def self.embedding_vector(response_hash)
      arr = response_hash["embedding"]
      raise Error, "Ollama: нет embedding в ответе" unless arr.is_a?(Array)

      arr.map(&:to_f)
    end

    def reachable?
      tags
      true
    rescue Error, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      false
    end

    private

    def post_json(path, payload)
      request_json(Net::HTTP::Post, path, body: JSON.generate(payload))
    end

    def get_json(path)
      request_json(Net::HTTP::Get, path, body: nil)
    end

    def request_json(method_class, path, body:)
      uri = URI.join("#{config.base_url}/", path.delete_prefix("/"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = config.open_timeout
      http.read_timeout = config.read_timeout

      req = method_class.new(uri)
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = body if body

      response = http.request(req)
      parse_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, e.message
    end

    def parse_response(response)
      body = response.body.to_s
      parsed = body.present? ? JSON.parse(body) : {}

      return parsed if response.is_a?(Net::HTTPSuccess)

      raise HttpError.new(
        "Ollama HTTP #{response.code}",
        status: response.code.to_i,
        body: parsed.presence || body
      )
    rescue JSON::ParserError
      raise HttpError.new("Ollama invalid JSON", status: response.code.to_i, body: body)
    end
  end
end
