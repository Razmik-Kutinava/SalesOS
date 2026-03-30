# frozen_string_literal: true

require "json"

module Imports
  # Сопоставление колонок файла полям Lead: эвристика + опционально Ollama (JSON).
  class ColumnMapper
    FIELD_KEYS = %w[company_name contact_name email phone stage].freeze

    KEYWORDS = {
      "company_name" => %w[company компани организация organization org firm название name company_name employer account],
      "contact_name" => %w[contact контакт имя fio person representative fullname contact_name],
      "email" => %w[email e-mail mail почта e_mail],
      "phone" => %w[phone tel телефон mobile мобильный телефон phone_number],
      "stage" => %w[stage стадия status статус pipeline]
    }.freeze

    # @param headers [Array<String>]
    # @return [Hash<String, String>] field_key => точное имя колонки из заголовков или пусто
    def self.heuristic(headers)
      return {} if headers.blank?

      taken = {}
      FIELD_KEYS.index_with do |field|
        pick = best_header_for(headers, field, taken)
        taken[pick] = true if pick.present?
        pick.to_s
      end.compact_blank
    end

    def self.best_header_for(headers, field, taken)
      keywords = KEYWORDS[field] || []
      scored = headers.each_with_index.map do |h, i|
        next if h.blank?

        hnorm = normalize(h)
        score = 0
        score += 10 if keywords.any? { |kw| hnorm.include?(normalize(kw)) }
        score += 2 if field == "company_name" && hnorm.match?(/^(company|комп|org)/i)
        score += 1 if h.length < 40
        [ h, score, i ]
      end.compact

      scored.sort_by! { |(_, s, idx)| [ -s, idx ] }
      scored.each do |(raw, _, _)|
        next if taken[raw]

        return raw
      end
      nil
    end

    def self.normalize(str)
      str.to_s.downcase.strip.gsub(/[^\p{L}\p{N}]+/u, " ")
    end

    # @return [Hash, Boolean] mapping, llm_used
    def self.build(headers:, use_llm: false, client: nil)
      base = heuristic(headers)
      return [ base, false ] unless use_llm

      llm = try_llm(headers, client) if client.respond_to?(:chat)
      return [ merged_mapping(base, llm), true ] if llm.present?

      [ base, false ]
    end

    def self.merged_mapping(heuristic_map, llm_map)
      out = {}
      FIELD_KEYS.each do |k|
        v = llm_map[k].presence || heuristic_map[k]
        out[k] = v if v.present?
      end
      out
    end

    def self.try_llm(headers, client)
      return {} if headers.blank?

      system = <<~SYSTEM.squish
        Ты помощник сопоставления колонок CSV/Excel с полями CRM.
        Ответь только JSON-объектом без markdown: ключи company_name, contact_name, email, phone, stage (строка или null).
        Значения — точное имя колонки из списка заголовков или null, если нет подходящей.
      SYSTEM
      user = "Заголовки: #{headers.to_json}"
      resp = client.chat(
        messages: [
          { "role" => "system", "content" => system },
          { "role" => "user", "content" => user }
        ],
        format: "json",
        options: { temperature: ENV.fetch("OLLAMA_IMPORT_MAPPING_TEMPERATURE", "0.1").to_f }
      )
      text = Llm::OllamaClient.message_content(resp)
      return {} if text.blank?

      data = JSON.parse(text)
      return {} unless data.is_a?(Hash)

      FIELD_KEYS.index_with { |k| data[k].presence || data[k.to_sym].presence }.compact_blank
    rescue JSON::ParserError, Llm::OllamaClient::Error, SocketError, Errno::ECONNREFUSED => e
      Rails.logger.warn("[Imports::ColumnMapper] LLM mapping failed: #{e.class}: #{e.message}")
      {}
    end
  end
end
