# frozen_string_literal: true

require "test_helper"

class AsrOpenaiWhisperClientTest < ActiveSupport::TestCase
  setup do
    @prev_key = ENV["OPENAI_API_KEY"]
    @prev_model = ENV["OPENAI_WHISPER_MODEL"]
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["OPENAI_WHISPER_MODEL"] = "whisper-1"
  end

  teardown do
    ENV["OPENAI_API_KEY"] = @prev_key
    ENV["OPENAI_WHISPER_MODEL"] = @prev_model
  end

  test "transcribe sends OPENAI_WHISPER_LANGUAGE when set" do
    ENV["OPENAI_WHISPER_LANGUAGE"] = "ru"
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: { text: "ok" }.to_json, headers: { "Content-Type" => "application/json" })

    Tempfile.create([ "lang", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_equal "ok", Asr::OpenaiWhisperClient.transcribe(f.path)
    end

    assert_requested(:post, "https://api.openai.com/v1/audio/transcriptions", times: 1)
  ensure
    ENV.delete("OPENAI_WHISPER_LANGUAGE")
  end

  test "transcribe returns text from JSON response" do
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: { text: "  hello world  " }.to_json, headers: { "Content-Type" => "application/json" })

    Tempfile.create([ "a", ".webm" ]) do |f|
      f.write("x")
      f.flush
      text = Asr::OpenaiWhisperClient.transcribe(f.path)
      assert_equal "hello world", text
    end
  end

  test "transcribe raises ConfigurationError without API key" do
    ENV.delete("OPENAI_API_KEY")
    Tempfile.create([ "b", ".wav" ]) do |f|
      f.write("x")
      f.flush
      assert_raises(Asr::OpenaiWhisperClient::ConfigurationError) do
        Asr::OpenaiWhisperClient.transcribe(f.path)
      end
    end
  end

  test "transcribe raises ApiError on HTTP error" do
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 401, body: { error: { message: "bad" } }.to_json)

    Tempfile.create([ "c", ".webm" ]) do |f|
      f.write("x")
      f.flush
      error = assert_raises(Asr::OpenaiWhisperClient::ApiError) do
        Asr::OpenaiWhisperClient.transcribe(f.path)
      end
      assert_equal 401, error.status
    end
  end

  test "transcribe raises ApiError when text empty" do
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: { text: "" }.to_json)

    Tempfile.create([ "d", ".mp3" ]) do |f|
      f.write("x")
      f.flush
      assert_raises(Asr::OpenaiWhisperClient::ApiError) do
        Asr::OpenaiWhisperClient.transcribe(f.path)
      end
    end
  end

  test "transcribe raises ApiError on invalid JSON body" do
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: "not-json")

    Tempfile.create([ "e", ".wav" ]) do |f|
      f.write("x")
      f.flush
      assert_raises(Asr::OpenaiWhisperClient::ApiError) do
        Asr::OpenaiWhisperClient.transcribe(f.path)
      end
    end
  end

  test "request hits OpenAI transcriptions endpoint" do
    stub = stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: { text: "endpoint_ok" }.to_json)

    Tempfile.create([ "f", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_equal "endpoint_ok", Asr::OpenaiWhisperClient.transcribe(f.path)
    end
    assert_requested stub
  end
end
