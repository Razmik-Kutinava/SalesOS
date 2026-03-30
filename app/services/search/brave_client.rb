# frozen_string_literal: true

require_relative "base_http_client"
require_relative "types"

module Search
  class BraveClient < BaseHttpClient
    PROVIDER = "brave"

    def initialize(api_key: nil, endpoint: nil)
      @api_key = (api_key || ENV["BRAVE_API_KEY"]).to_s.strip
      @endpoint = (endpoint || ENV["BRAVE_API_URL"]).to_s.strip.presence || "https://api.search.brave.com/res/v1/web/search"
      raise ConfigurationError, "BRAVE_API_KEY is blank" if @api_key.blank?
    end

    def search(query:, max_results: 5, country: nil, search_lang: nil, ui_lang: nil)
      payload = {
        "q" => query.to_s,
        "count" => max_results.to_i.clamp(1, 20)
      }
      payload["country"] = country.to_s if country.present?
      payload["search_lang"] = search_lang.to_s if search_lang.present?
      payload["ui_lang"] = ui_lang.to_s if ui_lang.present?

      json = post_json(
        url: @endpoint,
        headers: { "X-Subscription-Token" => @api_key },
        payload: payload
      )

      results = json.dig("web", "results").is_a?(Array) ? json.dig("web", "results") : []
      results.first(max_results).map do |r|
        url = r["url"] || r["link"]
        title = r["title"]
        snippet = r["description"] || r["snippet"]
        next if url.blank?

        SearchResult.new(url: url.to_s, title: title.to_s, snippet: snippet.to_s, provider: PROVIDER, raw: r)
      end.compact
    end
  end
end

