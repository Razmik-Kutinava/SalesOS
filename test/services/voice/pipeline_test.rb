# frozen_string_literal: true

require "test_helper"

class VoicePipelineTest < ActiveSupport::TestCase
  setup do
    @account = create_account!
    @user = create_user!(@account)
    @lead = create_lead!(@account)
    @saved_stub = ENV["VOICE_ASR_STUB"]
    @saved_text = ENV["VOICE_ASR_STUB_TEXT"]
  end

  teardown do
    @saved_stub.nil? ? ENV.delete("VOICE_ASR_STUB") : ENV["VOICE_ASR_STUB"] = @saved_stub
    @saved_text.nil? ? ENV.delete("VOICE_ASR_STUB_TEXT") : ENV["VOICE_ASR_STUB_TEXT"] = @saved_text
  end

  class ExplodingParser
    def call(**)
      raise "intent parser should not be called"
    end
  end

  test "blank transcript returns error and does not call intent parser" do
    ENV["VOICE_ASR_STUB"] = "1"
    ENV["VOICE_ASR_STUB_TEXT"] = "   "

    pipeline = Voice::Pipeline.new(user: @user, lead: @lead, intent_parser: ExplodingParser.new)

    audio = Rack::Test::UploadedFile.new(StringIO.new("x"), "audio/webm", original_filename: "v.webm")
    out = pipeline.call(audio)

    assert_equal false, out[:success]
    assert_equal "empty_transcript", out[:error]
  end

  test "transcript over max length returns error" do
    ENV["VOICE_ASR_STUB"] = "1"
    prev = ENV["VOICE_TRANSCRIPT_MAX_CHARS"]
    ENV["VOICE_TRANSCRIPT_MAX_CHARS"] = "5"
    ENV["VOICE_ASR_STUB_TEXT"] = "123456"

    pipeline = Voice::Pipeline.new(user: @user, lead: @lead, intent_parser: ExplodingParser.new)

    audio = Rack::Test::UploadedFile.new(StringIO.new("x"), "audio/webm", original_filename: "v.webm")
    out = pipeline.call(audio)

    assert_equal false, out[:success]
    assert_equal "transcript_too_long", out[:error]
  ensure
    prev.nil? ? ENV.delete("VOICE_TRANSCRIPT_MAX_CHARS") : ENV["VOICE_TRANSCRIPT_MAX_CHARS"] = prev
  end
end
