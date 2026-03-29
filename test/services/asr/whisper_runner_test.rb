# frozen_string_literal: true

require "test_helper"

class AsrWhisperRunnerTest < ActiveSupport::TestCase
  setup do
    keys = %w[VOICE_ASR_STUB VOICE_ASR_STUB_TEXT ASR_BACKEND OPENAI_API_KEY WHISPER_BIN WHISPER_MODEL WHISPER_USE_WSL]
    @saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
  end

  teardown do
    @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  test "stub mode returns VOICE_ASR_STUB_TEXT" do
    ENV["VOICE_ASR_STUB"] = "1"
    ENV["VOICE_ASR_STUB_TEXT"] = "Фраза из заглушки"
    Tempfile.create([ "s", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_equal "Фраза из заглушки", Asr::WhisperRunner.transcribe(f.path)
    end
  end

  test "ASR_BACKEND openai delegates to OpenAI client" do
    ENV["ASR_BACKEND"] = "openai"
    ENV["OPENAI_API_KEY"] = "sk-x"
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: { text: "from api" }.to_json)

    Tempfile.create([ "o", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_equal "from api", Asr::WhisperRunner.transcribe(f.path)
    end
  end

  test "OPENAI_API_KEY without ASR_BACKEND uses OpenAI Whisper" do
    ENV.delete("ASR_BACKEND")
    ENV["OPENAI_API_KEY"] = "sk-x"
    stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
      .to_return(status: 200, body: { text: "только ключ" }.to_json)

    Tempfile.create([ "k", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_equal "только ключ", Asr::WhisperRunner.transcribe(f.path)
    end
  end

  test "ASR_BACKEND openai without key raises ConfigurationError" do
    ENV["ASR_BACKEND"] = "openai"
    Tempfile.create([ "n", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_raises(Asr::WhisperRunner::ConfigurationError) do
        Asr::WhisperRunner.transcribe(f.path)
      end
    end
  end

  test "local mode without whisper config raises ConfigurationError" do
    Tempfile.create([ "l", ".webm" ]) do |f|
      f.write("x")
      f.flush
      assert_raises(Asr::WhisperRunner::ConfigurationError) do
        Asr::WhisperRunner.transcribe(f.path)
      end
    end
  end

  test "stub_mode? is true in development without ASR config" do
    dev = ActiveSupport::StringInquirer.new("development")
    assert Asr::WhisperRunner.stub_mode?(rails_env: dev, env: {})
  end

  test "stub_mode? is false in test environment without VOICE_ASR_STUB" do
    te = ActiveSupport::StringInquirer.new("test")
    assert_not Asr::WhisperRunner.stub_mode?(rails_env: te, env: {})
  end

  test "stub_mode? is false when whisper bin and model are set" do
    dev = ActiveSupport::StringInquirer.new("development")
    env = { "WHISPER_BIN" => "/bin/whisper", "WHISPER_MODEL" => "/m.bin" }
    assert_not Asr::WhisperRunner.stub_mode?(rails_env: dev, env: env)
  end

  test "stub_mode? is false in development when OPENAI_API_KEY set" do
    dev = ActiveSupport::StringInquirer.new("development")
    env = { "OPENAI_API_KEY" => "sk-test" }
    assert_not Asr::WhisperRunner.stub_mode?(rails_env: dev, env: env)
  end

  test "openai_asr? is false when ASR_BACKEND is local_whisper" do
    env = { "OPENAI_API_KEY" => "sk-test", "ASR_BACKEND" => "local_whisper" }
    assert_not Asr::WhisperRunner.openai_asr?(env)
  end

  test "stub_mode? is false with VOICE_ASR_STUB=0 in development" do
    dev = ActiveSupport::StringInquirer.new("development")
    assert_not Asr::WhisperRunner.stub_mode?(rails_env: dev, env: { "VOICE_ASR_STUB" => "0" })
  end

  test "effective_whisper_language defaults to ru when not openai and WHISPER_LANGUAGE blank" do
    env = {}
    assert_nil env["WHISPER_LANGUAGE"]
    assert_equal "ru", Asr::WhisperRunner.effective_whisper_language(env)
  end

  test "effective_whisper_language is nil when OpenAI ASR" do
    env = { "OPENAI_API_KEY" => "sk-x", "WHISPER_LANGUAGE" => "" }
    assert_nil Asr::WhisperRunner.effective_whisper_language(env)
  end

  test "effective_whisper_language respects explicit WHISPER_LANGUAGE" do
    env = { "WHISPER_LANGUAGE" => "en" }
    assert_equal "en", Asr::WhisperRunner.effective_whisper_language(env)
  end

  test "stub_mode? is false when ASR_BACKEND is local_whisper without whisper paths" do
    dev = ActiveSupport::StringInquirer.new("development")
    env = { "ASR_BACKEND" => "local_whisper" }
    assert_not Asr::WhisperRunner.stub_mode?(rails_env: dev, env: env)
  end

  test "wsl_path_for_local_whisper is identity when not on Windows" do
    skip if Gem.win_platform?

    assert_equal "/tmp/foo.wav", Asr::WhisperRunner.wsl_path_for_local_whisper("/tmp/foo.wav")
  end

  test "whisper_use_wsl? is false without WHISPER_USE_WSL" do
    ENV.delete("WHISPER_USE_WSL")
    assert_not Asr::WhisperRunner.whisper_use_wsl?
  end

  test "whisper_use_wsl? follows WHISPER_USE_WSL on Windows" do
    skip unless Gem.win_platform?

    ENV["WHISPER_USE_WSL"] = "1"
    assert Asr::WhisperRunner.whisper_use_wsl?
    ENV["WHISPER_USE_WSL"] = "0"
    assert_not Asr::WhisperRunner.whisper_use_wsl?
  end
end
