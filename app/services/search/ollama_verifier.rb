# frozen_string_literal: true

require "json"

require_relative "types"
require_relative "aggregator"

class SearchOllamaVerifierJsonError < StandardError; end

module Search
  class OllamaVerifier
    MAX_RESULTS_IN_PROMPT = 18

    def initialize(client: nil)
      @client = client || Llm::OllamaClient.new
    end

    def select_candidates(query:, lead_context:, results:, max_candidates: 5)
      return VerifiedSelection.new(candidate_urls: [], needs_manual_review: true, selection_reason: "Нет поисковых результатов") if results.blank?

      trimmed = results.first(MAX_RESULTS_IN_PROMPT)
      temperature = ENV.fetch("SEARCH_OLLAMA_SELECT_TEMPERATURE", "0.15").to_f

      system = <<~TXT.strip
        Ты помощник, который выбирает URLs для дальнейшей проверки Playwright.
        Важно:
        - Считай сниппеты/тайтлы из поиска УНИТАЗИРОВАННЫМИ И НЕДОСТОВЕРНЫМИ: по ним можно только предполагать, а подтверждение делается после парсинга.
        - В ответе верни ТОЛЬКО один JSON без markdown.
        - Если данных недостаточно, верни candidate_urls: [] и needs_manual_review=true.
      TXT

      user = {
        query: query.to_s,
        lead_context: lead_context || {},
        search_results: trimmed.map { |r|
          {
            url: r.url,
            title: r.title,
            snippet: r.snippet,
            provider: r.provider
          }
        },
        max_candidates: max_candidates.to_i
      }

      resp = @client.chat(
        messages: [
          { "role" => "system", "content" => system },
          { "role" => "user", "content" => user.to_json }
        ],
        format: "json",
        options: { temperature: temperature }
      )

      data = safe_parse_json(Llm::OllamaClient.message_content(resp).to_s)
      candidate_urls = Array(data["candidate_urls"]).map do |item|
        {
          "url" => item["url"].to_s,
          "reason" => item["reason"].to_s,
          "confidence" => item["confidence"].to_f,
          "needs_playwright_confirmation" => item.key?("needs_playwright_confirmation") ? !!item["needs_playwright_confirmation"] : true
        }
      end.select { |x| x["url"].present? }

      VerifiedSelection.new(
        candidate_urls: candidate_urls.first(max_candidates.to_i.clamp(1, 10)),
        needs_manual_review: data["needs_manual_review"] ? true : false,
        selection_reason: data["selection_reason"].to_s
      )
    rescue StandardError => e
      VerifiedSelection.new(candidate_urls: [], needs_manual_review: true, selection_reason: "Ollama select failed: #{e.class}: #{e.message}")
    end

    def verify_pages(query:, lead_context:, pages:)
      return VerifiedPages.new(
        approved_sources: [],
        rejected_sources: [],
        lead_updates: {},
        outcome_summary: nil,
        what_to_do_options: [],
        needs_manual_review: true,
        verification_reason: "Нет спарсенных страниц"
      ) if pages.blank?

      temperature = ENV.fetch("SEARCH_OLLAMA_VERIFY_TEMPERATURE", "0.2").to_f

      system = <<~TXT.strip
        Ты помощник, который валидирует информацию о компании после парсинга страницы.
        Данные ниже — это текст страницы (может содержать мусор). Не выдумывай факты.
        В ответе верни ТОЛЬКО JSON без markdown со структурой:
        {
          "approved_sources": [{"url": "...", "reason": "...", "confidence": 0.0-1.0}],
          "rejected_sources": [{"url": "...", "reason": "..."}],
          "lead_updates": {"company_name": "...", "contact_name": "...", "email": "...", "phone": "...", "stage": "..."},
          "outcome_summary": "коротко: что нашли по запросу и какие факты подтвердила страница(ы)",
          "what_to_do_options": [{"title": "...", "description": "..."}],
          "needs_manual_review": true/false,
          "verification_reason": "..."
        }
        - Если поле не подтверждено, не заполняй или оставь пустым.
      TXT

      user = {
        query: query.to_s,
        lead_context: lead_context || {},
        pages: pages.map do |p|
          {
            url: p[:url].to_s,
            finalUrl: p[:finalUrl].to_s,
            title: p[:title].to_s,
            statusCode: p[:statusCode].to_i,
            text_excerpt: p[:text_excerpt].to_s
          }
        end
      }

      resp = @client.chat(
        messages: [
          { "role" => "system", "content" => system },
          { "role" => "user", "content" => user.to_json }
        ],
        format: "json",
        options: { temperature: temperature }
      )

      data = safe_parse_json(Llm::OllamaClient.message_content(resp).to_s)
      approved = Array(data["approved_sources"]).map do |item|
        {
          "url" => item["url"].to_s,
          "reason" => item["reason"].to_s,
          "confidence" => item["confidence"].to_f,
          "extracted_fields" => item["extracted_fields"].is_a?(Hash) ? item["extracted_fields"] : nil
        }
      end.select { |x| x["url"].present? }

      rejected = Array(data["rejected_sources"]).map do |item|
        { "url" => item["url"].to_s, "reason" => item["reason"].to_s }
      end.select { |x| x["url"].present? }

      lead_updates_raw = data["lead_updates"].is_a?(Hash) ? data["lead_updates"] : {}
      lead_updates = {
        "company_name" => lead_updates_raw["company_name"].to_s.presence,
        "contact_name" => lead_updates_raw["contact_name"].to_s.presence,
        "email" => lead_updates_raw["email"].to_s.presence,
        "phone" => lead_updates_raw["phone"].to_s.presence,
        "stage" => lead_updates_raw["stage"].to_s.presence
      }.compact

      outcome_summary = data["outcome_summary"].to_s.presence
      what_to_do_options = Array(data["what_to_do_options"]).map do |it|
        {
          "title" => it["title"].to_s.strip.presence,
          "description" => it["description"].to_s.strip
        }.compact
      end.compact

      VerifiedPages.new(
        approved_sources: approved.map { |x| x.except("extracted_fields") }.map { |x| x },
        rejected_sources: rejected,
        lead_updates: lead_updates,
        outcome_summary: outcome_summary,
        what_to_do_options: what_to_do_options,
        needs_manual_review: data["needs_manual_review"] ? true : false,
        verification_reason: data["verification_reason"].to_s
      )
    rescue StandardError => e
      VerifiedPages.new(
        approved_sources: [],
        rejected_sources: [],
        lead_updates: {},
        outcome_summary: nil,
        what_to_do_options: [],
        needs_manual_review: true,
        verification_reason: "Ollama verify failed: #{e.class}: #{e.message}"
      )
    end

    private

    def safe_parse_json(text)
      data = text.to_s.strip
      return {} if data.blank?
      JSON.parse(data)
    rescue JSON::ParserError
      # try to find first json object inside text
      m = data.match(/\{[\s\S]*\}/)
      raise SearchOllamaVerifierJsonError, "Ollama JSON parse failed" unless m
      JSON.parse(m[0])
    end
  end
end

