# frozen_string_literal: true

require "test_helper"

class VoiceOllamaIntentParserTest < ActiveSupport::TestCase
  setup do
    @base = "http://127.0.0.1:11434"
    @config = Llm::OllamaClient::Configuration.new(
      base_url: @base,
      default_model: "m1",
      open_timeout: 2,
      read_timeout: 30
    )
    @client = Llm::OllamaClient.new(@config)
    @parser = Voice::OllamaIntentParser.new(client: @client)
    @lead = create_lead!(create_account!, company_name: "ACME", contact_name: "Ivan")
  end

  test "parses strict JSON from assistant content" do
    body = {
      intent: "add_note",
      slots: { note: "N" },
      assistant_message: "Добавил",
      need_approval: false
    }.to_json
    stub_request(:post, "#{@base}/api/chat")
      .to_return(status: 200, body: { message: { role: "assistant", content: body } }.to_json)

    out = @parser.call(transcript: "заметка", lead: @lead)
    assert_equal "add_note", out["intent"]
    assert_equal "N", out.dig("slots", "note")
  end

  test "extracts JSON object from prose around it" do
    wrapped = 'Sure {"intent":"noop","slots":{},"assistant_message":"x","need_approval":false} thanks'
    stub_request(:post, "#{@base}/api/chat")
      .to_return(status: 200, body: { message: { role: "assistant", content: wrapped } }.to_json)

    out = @parser.call(transcript: "x", lead: @lead)
    assert_equal "noop", out["intent"]
  end

  test "lead context includes company and next_call_at line" do
    @lead.update!(next_call_at: Time.zone.parse("2026-01-02T10:00:00Z"))
    stub_request(:post, "#{@base}/api/chat")
      .to_return(status: 200, body: { message: { role: "assistant", content: '{"intent":"noop","slots":{},"assistant_message":"","need_approval":false}' } }.to_json)

    @parser.call(transcript: "t", lead: @lead)
    assert_requested(:post, "#{@base}/api/chat") do |req|
      req.body.include?("ACME") && req.body.include?("next_call_at")
    end
  end

  test "returns noop structure when both parse attempts fail" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        { status: 200, body: { message: { role: "assistant", content: "not json" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: "still not" } }.to_json }
      )

    out = @parser.call(transcript: "x", lead: @lead)
    assert_equal "noop", out["intent"]
    assert_match(/разобрать JSON/i, out["assistant_message"].to_s)
  end

  test "retries once when first response is not json and second is valid" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        { status: 200, body: { message: { role: "assistant", content: "not json" } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: '{"intent":"noop","slots":{},"assistant_message":"x","need_approval":false}' } }.to_json }
      )

    out = @parser.call(transcript: "x", lead: @lead)
    assert_equal "noop", out["intent"]
    assert_requested(:post, "#{@base}/api/chat", times: 2)
  end

  test "retries when first JSON has invalid intent" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        { status: 200, body: { message: { role: "assistant", content: '{"intent":"not_an_intent","slots":{},"assistant_message":"","need_approval":false}' } }.to_json },
        { status: 200, body: { message: { role: "assistant", content: '{"intent":"noop","slots":{},"assistant_message":"ok","need_approval":false}' } }.to_json }
      )

    out = @parser.call(transcript: "x", lead: @lead)
    assert_equal "noop", out["intent"]
    assert_requested(:post, "#{@base}/api/chat", times: 2)
  end

  test "returns noop with error message on Ollama HttpError" do
    stub_request(:post, "#{@base}/api/chat").to_return(status: 500, body: "fail")

    out = @parser.call(transcript: "x", lead: @lead)
    assert_equal "noop", out["intent"]
    assert out["assistant_message"].to_s.include?("Ошибка") || out["_error"].present?
  end

  test "nil lead still calls model with placeholder context" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(status: 200, body: { message: { role: "assistant", content: '{"intent":"noop","slots":{},"assistant_message":"ok","need_approval":false}' } }.to_json)

    @parser.call(transcript: "t", lead: nil)
    assert_requested(:post, "#{@base}/api/chat") do |req|
      req.body.include?("не выбран")
    end
  end
end
