# frozen_string_literal: true

require "test_helper"

class OllamaHealthTest < ActionDispatch::IntegrationTest
  setup do
    @prev_host = ENV.fetch("OLLAMA_HOST", nil)
    @prev_model = ENV.fetch("OLLAMA_MODEL", nil)
    ENV["OLLAMA_HOST"] = "http://127.0.0.1:11434"
    ENV["OLLAMA_MODEL"] = "llama3.2"
  end

  teardown do
    if @prev_host
      ENV["OLLAMA_HOST"] = @prev_host
    else
      ENV.delete("OLLAMA_HOST")
    end
    if @prev_model
      ENV["OLLAMA_MODEL"] = @prev_model
    else
      ENV.delete("OLLAMA_MODEL")
    end
  end

  test "returns models when Ollama responds" do
    stub_request(:get, "http://127.0.0.1:11434/api/tags")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { models: [ { name: "llama3.2" } ] }.to_json
      )

    get "/health/ollama"

    assert_response :success
    json = JSON.parse(response.body)
    assert json["ok"]
    assert_includes json["models"], "llama3.2"
  end

  test "returns 503 when Ollama errors" do
    stub_request(:get, "http://127.0.0.1:11434/api/tags")
      .to_return(status: 503, body: "down")

    get "/health/ollama"

    assert_response :service_unavailable
    json = JSON.parse(response.body)
    assert_not json["ok"]
  end
end
