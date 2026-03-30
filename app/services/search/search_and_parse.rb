# frozen_string_literal: true

require_relative "types"
require_relative "aggregator"
require_relative "ollama_verifier"

require_relative "../fetch/playwright_client"
require "uri"

module Search
  class SearchAndParse
    # orchestrates: 3x search -> Ollama choose URLs -> Playwright fetch -> Ollama verify/approve
    def self.call(lead:, query:, actor_user_id: nil, trusted_domains: nil)
      new(lead: lead, query: query, actor_user_id: actor_user_id, trusted_domains: trusted_domains).call
    end

    def initialize(lead:, query:, actor_user_id: nil, trusted_domains: nil)
      @lead = lead
      @query = query.to_s.strip
      @actor_user_id = actor_user_id
      @account = lead.account
      @ollama = Llm::OllamaClient.new
      @fetch_client = Fetch::PlaywrightClient.new
      @trusted_domains = trusted_domains.to_s
    end

    def call
      raise ArgumentError, "query is blank" if @query.blank?

      lead_context = {
        lead_id: @lead.id,
        company_name: @lead.company_name,
        email: @lead.email
      }

      results = Aggregator.search_all(query: @query, max_results: max_search_results)
      selection = OllamaVerifier.new(client: @ollama).select_candidates(
        query: @query,
        lead_context: lead_context,
        results: Aggregator.dedup(results),
        max_candidates: max_candidates_for_playwright
      )

      pages = fetch_selected_pages(selection.candidate_urls)
      verified = if pages.present?
        OllamaVerifier.new(client: @ollama).verify_pages(
          query: @query,
          lead_context: lead_context,
          pages: pages
        )
      else
        VerifiedPages.new(
          approved_sources: [],
          rejected_sources: [],
          lead_updates: {},
          outcome_summary: nil,
          what_to_do_options: [],
          needs_manual_review: true,
          verification_reason: "Playwright не удалось получить страницы (allowlist не подошла или worker не настроен)"
        )
      end

      verified_with_stage = apply_stage_safety(verified)
      verified_with_stage = apply_trusted_fast_path(verified_with_stage)
      persist_result!(verified_with_stage, search_results: results, selection: selection, pages: pages)
      verified_with_stage
    rescue StandardError => e
      persist_failure!(e)
      raise
    end

    private

    def max_search_results
      ENV.fetch("SEARCH_MAX_RESULTS", "5").to_i
    end

    def max_candidates_for_playwright
      ENV.fetch("SEARCH_MAX_PAGES_TO_PARSE", "5").to_i
    end

    def parser_text_limit
      ENV.fetch("SEARCH_PARSER_TEXT_EXCERPT_LIMIT", "30000").to_i
    end

    def fetch_selected_pages(candidate_urls)
      return [] unless @fetch_client.configured?
      return [] if candidate_urls.blank?

      candidate_urls.map do |item|
        url = item["url"].presence || item[:url].presence
        next if url.blank?

        hostname = begin
          u = URI.parse(url.to_s)
          u&.host&.downcase
        rescue URI::InvalidURIError
          nil
        end

        next if hostname.blank?

        resp = @fetch_client.fetch(url: url, allowed_hosts: [hostname])
        next unless resp.is_a?(Hash)

        {
          url: resp["url"] || url,
          finalUrl: resp["finalUrl"],
          title: resp["title"],
          statusCode: resp["statusCode"],
          text_excerpt: resp["textContent"].to_s.truncate(parser_text_limit)
        }
      rescue Fetch::PlaywrightClient::NotAllowedError => e
        nil
      rescue Fetch::PlaywrightClient::ConfigurationError => _e
        nil
      rescue Fetch::PlaywrightClient::HttpError => _e
        nil
      end.compact
    end

    def apply_stage_safety(verified_pages)
      return verified_pages unless verified_pages.lead_updates.is_a?(Hash)

      updates = verified_pages.lead_updates.dup
      stage = updates["stage"] || updates[:stage]
      if stage.present?
        stage_norm = stage.to_s.downcase.strip
        updates["stage"] = Lead::STAGES.include?(stage_norm) ? stage_norm : nil
      end
      updates.compact!

      VerifiedPages.new(
        approved_sources: verified_pages.approved_sources,
        rejected_sources: verified_pages.rejected_sources,
        lead_updates: updates,
        outcome_summary: verified_pages.outcome_summary,
        what_to_do_options: verified_pages.what_to_do_options,
        needs_manual_review: verified_pages.needs_manual_review,
        verification_reason: verified_pages.verification_reason
      )
    end

    def apply_trusted_fast_path(verified_pages)
      trusted_hosts = parse_trusted_hosts(@trusted_domains)
      return verified_pages if trusted_hosts.empty?

      approved = Array(verified_pages.approved_sources)
      return verified_pages if approved.empty?

      approved_hosts = approved.map { |src| host_from_url(src["url"] || src[:url]) }.compact
      return verified_pages if approved_hosts.empty?

      all_trusted = approved_hosts.all? { |h| trusted_hosts.include?(h) }
      return verified_pages unless all_trusted

      VerifiedPages.new(
        approved_sources: verified_pages.approved_sources,
        rejected_sources: verified_pages.rejected_sources,
        lead_updates: verified_pages.lead_updates,
        outcome_summary: verified_pages.outcome_summary,
        what_to_do_options: verified_pages.what_to_do_options,
        needs_manual_review: false,
        verification_reason: "Источник из trusted_domains"
      )
    end

    def parse_trusted_hosts(raw)
      raw
        .to_s
        .split(",")
        .map { |s| s.strip.downcase }
        .reject(&:blank?)
        .to_set
    end

    def host_from_url(url)
      return nil if url.blank?
      URI.parse(url.to_s).host.to_s.downcase
    rescue URI::InvalidURIError
      nil
    end

    def persist_result!(verified_pages, search_results:, selection:, pages:)
      approved = verified_pages.approved_sources.is_a?(Array) ? verified_pages.approved_sources : []

      actor = @actor_user_id.present? ? User.find_by(id: @actor_user_id) : nil

      LeadEvent.create!(
        lead: @lead,
        actor: actor,
        event_type: "search_performed",
        payload: {
          query: @query,
          providers_count: {
            "serper" => search_results.count { |r| r.provider == "serper" },
            "tavily" => search_results.count { |r| r.provider == "tavily" },
            "brave" => search_results.count { |r| r.provider == "brave" }
          },
          selection_reason: selection.selection_reason,
          candidate_urls: Array(selection.candidate_urls).map { |c| c["url"] || c[:url] },
          parsed_pages: pages.map { |p| { url: p[:url], title: p[:title], statusCode: p[:statusCode] } }
        }
      )

      LeadEvent.create!(
        lead: @lead,
        actor: actor,
        event_type: "search_approved",
        payload: {
          approved_sources: approved,
          rejected_sources: verified_pages.rejected_sources,
          lead_updates: verified_pages.lead_updates,
          outcome_summary: verified_pages.outcome_summary,
          what_to_do_options: verified_pages.what_to_do_options,
          needs_manual_review: verified_pages.needs_manual_review,
          verification_reason: verified_pages.verification_reason
        }
      )

      apply_lead_updates!(verified_pages.lead_updates)

      store_search_outcome!(verified_pages)
    end

    def store_search_outcome!(verified_pages)
      outcome = {
        "query" => @query,
        "summary" => verified_pages.outcome_summary,
        "what_to_do_options" => verified_pages.what_to_do_options,
        "needs_manual_review" => verified_pages.needs_manual_review,
        "verification_reason" => verified_pages.verification_reason,
        "approved_sources" => Array(verified_pages.approved_sources)
      }
      @lead.update!(metadata: (@lead.metadata || {}).merge("search_outcome" => outcome))
    end

    def apply_lead_updates!(lead_updates)
      return unless lead_updates.is_a?(Hash) && lead_updates.any?

      allowed = %w[company_name contact_name email phone stage]
      attrs = lead_updates.stringify_keys.slice(*allowed)
      attrs["stage"] = attrs["stage"].to_s.downcase.strip if attrs["stage"].present?

      @lead.update!(attrs.compact)
    end

    def persist_failure!(e)
      # Do not spam lead history on internal failures; controller decides how to display.
      raise
    end
  end
end

