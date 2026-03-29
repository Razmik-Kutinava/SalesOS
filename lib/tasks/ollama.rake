# frozen_string_literal: true

namespace :ollama do
  desc "Замер latency и простых проб качества. ENV: OLLAMA_HOST, OLLAMA_MODEL; опционально OLLAMA_BENCHMARK_MODELS=m1,m2,m3"
  task benchmark: :environment do
    client = Llm::OllamaClient.new
    names = ENV["OLLAMA_BENCHMARK_MODELS"].to_s.split(",").map(&:strip).reject(&:blank?)
    names = [ client.config.default_model ] if names.empty?

    puts "Ollama: #{client.config.base_url}"
    puts "Модели для прогона: #{names.join(', ')}"
    puts ""

    names.each do |model|
      puts "--- #{model} ---"
      s = Llm::OllamaProbe.suite(client, model: model)
      puts format("  GET /api/tags:     %.1f ms", s.tags_ms || -1)
      puts format("  tiny chat (pong): %.1f ms", s.chat_ms || -1)
      puts format("  пробы качества:   %d / %d (ratio %.2f)", s.probe_passed, s.probe_total, s.probe_ratio)
      s.probes.each do |p|
        status = p.passed ? "OK" : "FAIL"
        puts format("    [%s] %-14s %6.1f ms  %s", status, p.id, p.latency_ms, p.reply_preview)
      end
      puts ""
    end
  rescue Llm::OllamaClient::Error => e
    warn "Ollama error: #{e.class}: #{e.message}"
    exit 1
  end

  desc "Проверить доступность Ollama (tags + короткий chat). ENV: OLLAMA_HOST, OLLAMA_MODEL"
  task ping: :environment do
    client = Llm::OllamaClient.new
    puts "Base URL: #{client.config.base_url}"
    puts "Default model: #{client.config.default_model}"
    puts "GET /api/tags ..."
    tags = client.tags
    names = tags.fetch("models", []).filter_map { |m| m["name"] }
    puts "Models (#{names.size}): #{names.first(5).join(', ')}#{names.size > 5 ? '…' : ''}"
    puts "POST /api/chat (smoke) ..."
    response = client.chat(messages: [ { "role" => "user", "content" => "Reply with exactly: OK" } ])
    content = Llm::OllamaClient.message_content(response)
    puts "Assistant: #{content}"
    puts "Done."
  rescue Llm::OllamaClient::Error => e
    warn "Ollama error: #{e.class}: #{e.message}"
    exit 1
  end
end
