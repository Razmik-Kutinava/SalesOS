# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Search
  class BaseHttpClient
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

    private

    def post_json(url:, headers:, payload:, open_timeout: nil, read_timeout: nil)
      uri = URI.parse(url.to_s)
      raise ArgumentError, "url is blank" if uri.to_s.blank?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = (open_timeout || 5).to_i
      http.read_timeout = (read_timeout || 30).to_i

      req = Net::HTTP::Post.new(uri.request_uri)
      headers.to_h.each { |k, v| req[k.to_s] = v.to_s }
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = JSON.generate(payload)

      res = http.request(req)
      body = res.body.to_s

      parsed = JSON.parse(body.presence || "{}")
      return parsed if res.is_a?(Net::HTTPSuccess)

      raise HttpError.new("HTTP #{res.code} from #{uri.host}", status: res.code.to_i, body: parsed.presence || body)
    rescue JSON::ParserError
      raise HttpError.new("Non-JSON response from #{uri.host}", status: res&.code&.to_i, body: body)
    end
  end
end

