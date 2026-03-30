# frozen_string_literal: true

require_relative "base_http_client"
require_relative "types"

module Search
  class SerperClient < BaseHttpClient
    PROVIDER = "serper"

    def initialize(api_key: nil, endpoint: nil)
      @api_key = (api_key || ENV["SERPER_API_KEY"]).to_s.strip
      @endpoint = (endpoint || ENV["SERPER_API_URL"]).to_s.strip.presence || "https://google.serper.dev/search"
      raise ConfigurationError, "SERPER_API_KEY is blank" if @api_key.blank?
    end

    def search(query:, max_results: 5, gl: nil, hl: nil)
      payload = {
        "q" => query.to_s,
        "num" => max_results.to_i
      }
      payload["gl"] = gl.to_s if gl.present?
      payload["hl"] = hl.to_s if hl.present?

      json = post_json(
        url: @endpoint,
        headers: { "X-API-KEY" => @api_key },
        payload: payload
      )

      organic = json["organic"].is_a?(Array) ? json["organic"] : []
      organic.first(max_results).map do |r|
        url = r["link"] || r["url"]
        title = r["title"]
        snippet = r["snippet"]
        next if url.blank?

        SearchResult.new(url: url.to_s, title: title.to_s, snippet: snippet.to_s, provider: PROVIDER, raw: r)
      end.compact
    end
  end
end

