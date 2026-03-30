# frozen_string_literal: true

require "uri"

require_relative "types"
require_relative "serper_client"
require_relative "tavily_client"
require_relative "brave_client"

module Search
  class Aggregator
    DEFAULT_MAX_RESULTS = 5
    DEFAULT_PROVIDER_ORDER = %w[serper tavily brave].freeze

    def self.enabled_providers
      %w[serper tavily brave].select do |p|
        env_key =
          case p
          when "serper" then "SERPER_API_KEY"
          when "tavily" then "TAVILY_API_KEY"
          when "brave" then "BRAVE_API_KEY"
          end
        ENV[env_key].to_s.strip.present?
      end
    end

    def self.search_all(query:, max_results: DEFAULT_MAX_RESULTS, provider_order: nil)
      order = (provider_order || ENV["SEARCH_PROVIDER_ORDER"]).to_s.strip.presence&.split(",")&.map(&:strip) || DEFAULT_PROVIDER_ORDER
      providers = order & enabled_providers
      return [] if providers.empty?

      out = []
      providers.each do |provider|
        client = build_client(provider)
        out.concat(client.search(query: query, max_results: max_results))
      end

      out
    end

    def self.dedup(results)
      seen = {}
      results.each_with_object([]) do |r, arr|
        canon = canonicalize_url(r.url)
        next if canon.blank?
        next if seen[canon]
        seen[canon] = true
        arr << r
      end
    end

    def self.canonicalize_url(url)
      u = URI.parse(url.to_s)
      return nil if u.scheme.blank? || u.host.blank?

      # remove typical tracking params
      if u.query.present?
        q = URI.decode_www_form(u.query).reject do |k, _v|
          k.to_s.start_with?("utm_") || %w[gclid fbclid].include?(k.to_s)
        end
        u.query = q.empty? ? nil : URI.encode_www_form(q)
      end

      u.fragment = nil
      u.to_s
    rescue URI::InvalidURIError
      nil
    end

    def self.build_client(provider)
      case provider
      when "serper" then SerperClient.new
      when "tavily" then TavilyClient.new
      when "brave" then BraveClient.new
      else
        raise ArgumentError, "Unknown provider: #{provider}"
      end
    end
  end
end

