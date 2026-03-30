# frozen_string_literal: true

require "json"
require "net/http"
require "set"
require "uri"

module Fetch
  # HTTP-клиент к отдельному Playwright-воркеру (см. playwright-worker/, Dockerfile.playwright).
  class PlaywrightClient
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class NotAllowedError < Error; end
    class HttpError < Error
      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end
    end

    def initialize(base_url: nil, token: nil, allowed_hosts: nil, open_timeout: nil, read_timeout: nil)
      @base_url = (base_url || ENV["PLAYWRIGHT_FETCH_URL"].to_s).strip.chomp("/")
      @token = (token || ENV["PLAYWRIGHT_FETCH_TOKEN"]).to_s
      @allowed_hosts = self.class.parse_allowed_hosts(allowed_hosts || ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"])
      @open_timeout = (open_timeout || ENV.fetch("PLAYWRIGHT_FETCH_OPEN_TIMEOUT", "5")).to_i
      @read_timeout = (read_timeout || ENV.fetch("PLAYWRIGHT_FETCH_READ_TIMEOUT", "120")).to_i
    end

    def self.parse_allowed_hosts(raw)
      parts =
        case raw
        when Array then raw
        when Set then raw.to_a
        else raw.to_s.split(",")
        end

      parts.map { |s| s.to_s.strip.downcase }.reject(&:blank?).to_set
    end

    def configured?
      @base_url.present?
    end

    # @param wait_until [String] "load" или "domcontentloaded"
    # @return [Hash] ответ воркера (ключи string)
    def fetch(url:, wait_until: "load", timeout_ms: nil, allowed_hosts: nil)
      raise ConfigurationError, "PLAYWRIGHT_FETCH_URL не задан" unless configured?

      uri = parse_http_url!(url)
      hostname = uri.host.to_s.downcase
      allowed_set = parse_allowed_hosts(allowed_hosts)
      raise NotAllowedError, "Запрещённый/небезопасный хост: #{hostname}" unless safe_hostname?(hostname)

      if allowed_set.present?
        raise NotAllowedError, "Домен не в allowlist запроса: #{hostname}" unless allowed_set.include?(hostname)
      else
        raise NotAllowedError, "Домен не в allowlist: #{hostname}" unless host_allowed?(hostname)
      end

      target = URI.join("#{@base_url}/", "v1/fetch")
      body = JSON.generate(
        {
          "url" => url.to_s,
          "waitUntil" => wait_until.to_s == "domcontentloaded" ? "domcontentloaded" : "load",
          "timeout" => timeout_ms,
          "allowedHosts" => allowed_set.to_a.presence
        }.compact
      )

      http = Net::HTTP.new(target.host, target.port)
      http.use_ssl = (target.scheme == "https")
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout

      req = Net::HTTP::Post.new(target.request_uri)
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req["Authorization"] = "Bearer #{@token}" if @token.present?
      req.body = body

      res = http.request(req)
      parsed = JSON.parse(res.body.to_s.presence || "{}")
      return parsed if res.is_a?(Net::HTTPSuccess)

      raise HttpError.new(
        "Playwright worker HTTP #{res.code}",
        status: res.code.to_i,
        body: parsed
      )
    rescue JSON::ParserError
      raise HttpError.new("Playwright worker: невалидный JSON", status: res&.code.to_i, body: res&.body)
    end

    private

    def parse_http_url!(url)
      u = URI.parse(url.to_s)
      raise NotAllowedError, "Только http/https" unless %w[http https].include?(u.scheme)

      u
    end

    def host_allowed?(hostname)
      return false if @allowed_hosts.empty?

      @allowed_hosts.include?(hostname)
    end

    def safe_hostname?(hostname)
      # Безопасность от SSRF: запрещаем loopback и private IP, если host — literal IP/localhost.
      return false if hostname == "localhost" || hostname.end_with?(".localhost")

      ip = hostname
      return true unless ip.match?(/\A\d{1,3}(\.\d{1,3}){3}\z|\A[0-9a-fA-F:]+\z/)

      begin
        require "ipaddr"
        addr = IPAddr.new(ip)
        return false if addr.loopback?
        return false if addr.private?
        return false if addr.link_local?
        return true
      rescue ArgumentError
        true
      end
    end
  end
end
