# frozen_string_literal: true

require "test_helper"

class LlmOllamaProbeTest < ActiveSupport::TestCase
  setup do
    @base = "http://127.0.0.1:11434"
    @config = Llm::OllamaClient::Configuration.new(
      base_url: @base,
      default_model: "probe-model",
      open_timeout: 2,
      read_timeout: 30
    )
    @client = Llm::OllamaClient.new(@config)
  end

  test "measure_tags records latency and model names" do
    stub_request(:get, "#{@base}/api/tags")
      .to_return(
        status: 200,
        body: { models: [ { name: "a:latest" }, { name: "b:latest" } ] }.to_json
      )

    m = Llm::OllamaProbe.measure_tags(@client)
    assert m.success?
    assert m.latency_ms >= 0
    assert_equal %w[a:latest b:latest], m.model_names
  end

  test "measure_tags error sets error message" do
    stub_request(:get, "#{@base}/api/tags").to_return(status: 503, body: "no")
    m = Llm::OllamaProbe.measure_tags(@client)
    assert_not m.success?
    assert_equal [], m.model_names
    assert m.error.present?
  end

  test "measure_chat returns content and latency" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        status: 200,
        body: { message: { role: "assistant", content: "hello" } }.to_json
      )

    m = Llm::OllamaProbe.measure_chat(
      @client,
      messages: [ { "role" => "user", "content" => "hi" } ]
    )
    assert m.success?
    assert_equal "hello", m.content
    assert_equal "probe-model", m.model
    assert m.latency_ms >= 0
  end

  test "measure_chat uses explicit model" do
    stub_request(:post, "#{@base}/api/chat")
      .with(body: /"model":"other"/)
      .to_return(status: 200, body: { message: { role: "assistant", content: "x" } }.to_json)

    m = Llm::OllamaProbe.measure_chat(
      @client,
      messages: [ { "role" => "user", "content" => "hi" } ],
      model: "other"
    )
    assert m.success?
    assert_equal "other", m.model
  end

  test "measure_chat captures error" do
    stub_request(:post, "#{@base}/api/chat").to_return(status: 500, body: "x")
    m = Llm::OllamaProbe.measure_chat(@client, messages: [ { "role" => "user", "content" => "x" } ])
    assert_not m.success?
    assert m.error.present?
  end

  test "measure_tiny_chat uses short prompt" do
    stub_request(:post, "#{@base}/api/chat")
      .with(body: /pong/)
      .to_return(status: 200, body: { message: { role: "assistant", content: "pong" } }.to_json)

    m = Llm::OllamaProbe.measure_tiny_chat(@client)
    assert m.success?
    assert_match(/pong/i, m.content)
  end

  test "run_probe passes when matcher matches" do
    probe = {
      id: "t1",
      messages: [ { "role" => "user", "content" => "x" } ],
      match: ->(text) { text.include?("391") }
    }
    stub_request(:post, "#{@base}/api/chat")
      .to_return(status: 200, body: { message: { role: "assistant", content: "391" } }.to_json)

    r = Llm::OllamaProbe.run_probe(@client, probe)
    assert r.passed
    assert_equal "t1", r.id
    assert r.latency_ms >= 0
  end

  test "run_probe fails when matcher rejects" do
    probe = {
      id: "t2",
      messages: [ { "role" => "user", "content" => "x" } ],
      match: ->(text) { text.include?("NOPE") }
    }
    stub_request(:post, "#{@base}/api/chat")
      .to_return(status: 200, body: { message: { role: "assistant", content: "yes" } }.to_json)

    r = Llm::OllamaProbe.run_probe(@client, probe)
    assert_not r.passed
  end

  test "run_probes returns one result per probe" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        { status: 200, body: { message: { role: "assistant", content: "391" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "Paris" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: '{"ok":true}' } }.to_json }
      )

    list = Llm::OllamaProbe.run_probes(@client, probes: Llm::OllamaProbe::DEFAULT_PROBES)
    assert_equal Llm::OllamaProbe::DEFAULT_PROBES.size, list.size
    assert list.all? { |r| r.id.present? }
  end

  test "suite aggregates tags tiny chat and probes" do
    stub_request(:get, "#{@base}/api/tags")
      .to_return(body: { models: [ { name: "probe-model" } ] }.to_json)
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        { status: 200, body: { message: { role: "assistant", content: "pong" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "391" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "Paris" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: '{"ok":true,"n":1}' } }.to_json }
      )

    s = Llm::OllamaProbe.suite(@client, probes: Llm::OllamaProbe::DEFAULT_PROBES)
    assert_equal "probe-model", s.model
    assert s.tags_ms.present?
    assert s.chat_ms.present?
    assert_equal Llm::OllamaProbe::DEFAULT_PROBES.size, s.probe_total
    assert_operator s.probe_passed, :>=, 0
    assert s.probe_ratio >= 0.0
  end

  test "compare_models runs suite per model" do
    stub_request(:get, "#{@base}/api/tags")
      .to_return(body: { models: [ { name: "m1" }, { name: "m2" } ] }.to_json)
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        { status: 200, body: { message: { role: "assistant", content: "pong" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "391" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "Paris" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: '{"ok":true}' } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "pong" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "391" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "Paris" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: '{"ok":true}' } }.to_json }
      )

    rows = Llm::OllamaProbe.compare_models(@client, %w[m1 m2])
    assert_equal 2, rows.size
    assert_equal %w[m1 m2], rows.map(&:model)
  end

  test "DEFAULT_PROBES are frozen and have ids" do
    assert Llm::OllamaProbe::DEFAULT_PROBES.frozen?
    Llm::OllamaProbe::DEFAULT_PROBES.each do |p|
      assert p[:id].present?
      assert p[:messages].present?
      assert p[:match].respond_to?(:call)
    end
  end

  test "SuiteSummary probe_ratio zero when no probes" do
    s = Llm::OllamaProbe::SuiteSummary.new(
      model: "x",
      tags_ms: 1.0,
      chat_ms: 2.0,
      probes: [],
      probe_passed: 0,
      probe_total: 0
    )
    assert_equal 0.0, s.probe_ratio
  end

  test "SuiteSummary probe_ratio counts passed" do
    pr = Llm::OllamaProbe::ProbeResult.new(id: "a", passed: true, latency_ms: 1.0, reply_preview: "")
    s = Llm::OllamaProbe::SuiteSummary.new(
      model: "x",
      tags_ms: 1.0,
      chat_ms: 2.0,
      probes: [ pr ],
      probe_passed: 1,
      probe_total: 2
    )
    assert_equal 0.5, s.probe_ratio
  end

  test "monotonic_ms increases over time" do
    t1 = Llm::OllamaProbe.monotonic_ms
    sleep 0.01
    t2 = Llm::OllamaProbe.monotonic_ms
    assert_operator t2, :>, t1
  end
end
