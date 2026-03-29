# frozen_string_literal: true

require "test_helper"

# Реальные HTTP-вызовы к локальному Ollama. В CI по умолчанию пропускаются.
# Запуск: OLLAMA_LIVE_BENCHMARK=1 bin/rails test test/integration/ollama_live_benchmark_test.rb
class OllamaLiveBenchmarkTest < ActionDispatch::IntegrationTest
  setup do
    @live = ENV["OLLAMA_LIVE_BENCHMARK"].to_s == "1"
    skip "Set OLLAMA_LIVE_BENCHMARK=1 and run Ollama on OLLAMA_HOST" unless @live
    WebMock.allow_net_connect!
  end

  teardown do
    WebMock.disable_net_connect!(allow_localhost: false) if @live
  end

  test "live: tags returns models including default model name" do
    client = Llm::OllamaClient.new
    m = Llm::OllamaProbe.measure_tags(client)
    assert m.success?, "Ollama недоступен по #{client.config.base_url}: #{m.error}"
    assert m.model_names.any?, "Список моделей пуст — сделайте ollama pull"
    token = client.config.default_model.split(":").first
    assert m.model_names.any? { |n| n.include?(token) },
      "OLLAMA_MODEL=#{client.config.default_model} ни одна строка из ollama list не содержит #{token}: #{m.model_names.inspect}"
  end

  test "live: tiny chat responds within sane wall time" do
    client = Llm::OllamaClient.new
    chat = Llm::OllamaProbe.measure_tiny_chat(client)
    assert chat.success?, chat.error.to_s
    assert chat.content.present?
    assert_operator chat.latency_ms, :<, 600_000.0, "Ответ дольше 10 минут — проверьте GPU/модель"
  end

  test "live: suite reports timings and probe stats" do
    client = Llm::OllamaClient.new
    s = Llm::OllamaProbe.suite(client)
    assert s.tags_ms.present?
    assert s.chat_ms.present?
    assert_equal Llm::OllamaProbe::DEFAULT_PROBES.size, s.probe_total
    assert_operator s.probe_passed, :>=, 0
    assert_operator s.probe_passed, :<=, s.probe_total
  end

  test "live: optional second model from OLLAMA_BENCHMARK_MODEL2" do
    name = ENV["OLLAMA_BENCHMARK_MODEL2"].to_s.strip
    skip "Set OLLAMA_BENCHMARK_MODEL2 to compare two models" if name.blank?

    client = Llm::OllamaClient.new
    s = Llm::OllamaProbe.suite(client, model: name)
    assert s.tags_ms.present?
    assert_operator s.probe_passed, :>=, 0
  end
end
