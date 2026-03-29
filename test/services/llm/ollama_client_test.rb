# frozen_string_literal: true

require "test_helper"

class LlmOllamaClientTest < ActiveSupport::TestCase
  setup do
    @base = "http://127.0.0.1:11434"
    @config = Llm::OllamaClient::Configuration.new(
      base_url: @base,
      default_model: "test-model",
      open_timeout: 2,
      read_timeout: 5
    )
    @client = Llm::OllamaClient.new(@config)
  end

  test "chat posts json and returns parsed body" do
    stub_request(:post, "#{@base}/api/chat")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { message: { role: "assistant", content: "hello" } }.to_json
      )

    result = @client.chat(messages: [ { "role" => "user", "content" => "hi" } ])
    assert_equal "hello", Llm::OllamaClient.message_content(result)
    assert_requested :post, "#{@base}/api/chat",
      times: 1,
      headers: { "Content-Type" => "application/json" }
  end

  test "tags get request" do
    stub_request(:get, "#{@base}/api/tags")
      .to_return(status: 200, body: { models: [ { name: "m1" } ] }.to_json)

    result = @client.tags
    assert_equal "m1", result.dig("models", 0, "name")
  end

  test "http error raises HttpError" do
    stub_request(:get, "#{@base}/api/tags")
      .to_return(status: 500, body: "fail")

    error = assert_raises(Llm::OllamaClient::HttpError) { @client.tags }
    assert_equal 500, error.status
  end

  test "reachable? is false on connection failure" do
    stub_request(:get, "#{@base}/api/tags").to_raise(Errno::ECONNREFUSED.new)
    assert_not @client.reachable?
  end

  test "empty messages raises ArgumentError" do
    assert_raises(ArgumentError) { @client.chat(messages: []) }
  end

  test "chat passes options to Ollama body" do
    stub_request(:post, "#{@base}/api/chat")
      .with do |req|
        body = JSON.parse(req.body)
        body["options"] == { "temperature" => 0.1 }
      end
      .to_return(status: 200, body: { message: { content: "{}" } }.to_json)

    @client.chat(
      messages: [ { "role" => "user", "content" => "x" } ],
      options: { "temperature" => 0.1 }
    )
    assert_requested :post, "#{@base}/api/chat"
  end

  test "embed posts to api/embeddings and returns vector" do
    stub_request(:post, "#{@base}/api/embeddings")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { embedding: [ 0.1, 0.2, 0.3 ] }.to_json
      )

    out = @client.embed(prompt: "hello")
    assert_equal [ 0.1, 0.2, 0.3 ], Llm::OllamaClient.embedding_vector(out)
  end
end
