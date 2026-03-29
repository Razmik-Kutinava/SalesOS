# frozen_string_literal: true

module Llm
  # Локальные замеры latency и простые «пробы» качества для выбора модели Ollama.
  # См. test/README.md (раздел Ollama benchmark) и rake ollama:benchmark.
  class OllamaProbe
    ChatMeasurement = Data.define(:model, :latency_ms, :content, :error) do
      def success? = error.nil?
    end

    TagsMeasurement = Data.define(:latency_ms, :model_names, :error) do
      def success? = error.nil?
    end

    ProbeResult = Data.define(:id, :passed, :latency_ms, :reply_preview)

    SuiteSummary = Data.define(:model, :tags_ms, :chat_ms, :probes, :probe_passed, :probe_total) do
      def probe_ratio
        return 0.0 if probe_total.to_i <= 0

        (probe_passed.to_f / probe_total).round(3)
      end
    end

    # Короткие проверки: ответ должен удовлетворять предикату (для сравнения моделей на одной машине).
    DEFAULT_PROBES = [
      {
        id: "math_product",
        messages: [ { "role" => "user", "content" => "Calculate 17 * 23. Reply with the integer only, no words." } ],
        match: ->(text) { text.to_s.match?(/\b391\b/) }
      },
      {
        id: "capital_fr",
        messages: [ { "role" => "user", "content" => "What is the capital of France? One English word only." } ],
        match: ->(text) { text.to_s.match?(/\bParis\b/i) }
      },
      {
        id: "json_shape",
        messages: [
          { "role" => "system", "content" => "You reply with JSON only, no markdown." },
          { "role" => "user", "content" => 'Return exactly: {"ok":true,"n":1}' }
        ],
        match: ->(text) { text.to_s.include?('"ok"') && text.to_s.include?("true") }
      }
    ].freeze

    class << self
      def measure_tags(client)
        t0 = monotonic_ms
        names = client.tags.fetch("models", []).filter_map { |m| m["name"] }
        TagsMeasurement.new(latency_ms: monotonic_ms - t0, model_names: names, error: nil)
      rescue Llm::OllamaClient::Error, SocketError, SystemCallError => e
        TagsMeasurement.new(latency_ms: 0.0, model_names: [], error: e.message)
      end

      def measure_chat(client, messages:, model: nil)
        used_model = model.presence || client.config.default_model
        t0 = monotonic_ms
        response = client.chat(messages: messages, model: model)
        latency_ms = monotonic_ms - t0
        content = Llm::OllamaClient.message_content(response)
        ChatMeasurement.new(model: used_model, latency_ms: latency_ms, content: content.to_s, error: nil)
      rescue Llm::OllamaClient::Error, SocketError, SystemCallError => e
        latency_ms = monotonic_ms - t0
        ChatMeasurement.new(model: used_model, latency_ms: latency_ms, content: "", error: e.message)
      end

      # Один короткий запрос — типичная «базовая» латентность чата.
      def measure_tiny_chat(client, model: nil)
        measure_chat(
          client,
          messages: [ { "role" => "user", "content" => "Say exactly: pong" } ],
          model: model
        )
      end

      def run_probe(client, probe, model: nil)
        m = measure_chat(client, messages: probe.fetch(:messages), model: model)
        passed = m.success? && probe[:match].call(m.content)
        preview = m.content.to_s.tr("\n", " ")[0, 120]
        ProbeResult.new(id: probe[:id], passed: passed, latency_ms: m.latency_ms, reply_preview: preview)
      end

      def run_probes(client, probes: DEFAULT_PROBES, model: nil)
        probes.map { |p| run_probe(client, p, model: model) }
      end

      # Полный снимок: tags + tiny chat + набор проб (качество/скорость).
      def suite(client, probes: DEFAULT_PROBES, model: nil)
        tag = measure_tags(client)
        tags_ms = tag.success? ? tag.latency_ms : nil
        tiny = measure_tiny_chat(client, model: model)
        chat_ms = tiny.success? ? tiny.latency_ms : nil
        results = run_probes(client, probes: probes, model: model)
        passed = results.count(&:passed)
        SuiteSummary.new(
          model: model.presence || client.config.default_model,
          tags_ms: tags_ms,
          chat_ms: chat_ms,
          probes: results,
          probe_passed: passed,
          probe_total: results.size
        )
      end

      # Сравнение нескольких имён моделей (как в `ollama list`).
      def compare_models(client, model_names, probes: DEFAULT_PROBES)
        model_names.compact.uniq.filter_map do |name|
          suite(client, probes: probes, model: name)
        end
      end

      def monotonic_ms
        Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000.0
      end
    end
  end
end
