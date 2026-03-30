# frozen_string_literal: true

require_relative "base_http_client"
require_relative "types"

module Search
  class TavilyClient < BaseHttpClient
    PROVIDER = "tavily"

    def initialize(api_key: nil, endpoint: nil)
      @api_key = (api_key || ENV["TAVILY_API_KEY"]).to_s.strip
      @endpoint = (endpoint || ENV["TAVILY_API_URL"]).to_s.strip.presence || "https://api.tavily.com/search"
      raise ConfigurationError, "TAVILY_API_KEY is blank" if @api_key.blank?
    end

    def search(query:, max_results: 5)
      payload = {
        "query" => query.to_s,
        "max_results" => max_results.to_i,
        # Default: fewer tokens & lower cost for MVP.
        "search_depth" => (ENV["TAVILY_SEARCH_DEPTH"] || "basic").to_s
      }

      json = post_json(
        url: @endpoint,
        headers: { "Authorization" => "Bearer #{@api_key}" },
        payload: payload
      )

      results = json["results"].is_a?(Array) ? json["results"] : []
      results.first(max_results).map do |r|
        url = r["url"]
        title = r["title"]
        snippet = r["content"] || r["snippet"] || r["description"]
        next if url.blank?

        SearchResult.new(url: url.to_s, title: title.to_s, snippet: snippet.to_s, provider: PROVIDER, raw: r)
      end.compact
    end
  end
end

