# frozen_string_literal: true

require "test_helper"

class VoiceCommandsTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "voice-tester@test.dev")
    @lead = create_lead!(@account)
    ENV["VOICE_ASR_STUB"] = "1"
    ENV["VOICE_ASR_STUB_TEXT"] = "Добавь заметку: проверка голоса"

    stub_request(:post, %r{http://127\.0\.0\.1:11434/api/chat}).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        message: {
          role: "assistant",
          content: '{"intent":"add_note","slots":{"note":"проверка голоса"},"assistant_message":"Заметка добавлена.","need_approval":false}'
        }
      }.to_json
    )
  end

  teardown do
    ENV.delete("VOICE_ASR_STUB")
    ENV.delete("VOICE_ASR_STUB_TEXT")
  end

  test "requires login" do
    post voice_lead_path(@lead), params: {}
    assert_redirected_to login_path
  end

  test "POST console voice without lead creates lead when stub and model return create_lead" do
    Lead.update_all(discarded_at: Time.current)
    stub_request(:post, %r{http://127\.0\.0\.1:11434/api/chat}).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        message: {
          role: "assistant",
          content: '{"intent":"create_lead","slots":{"company_name":"FromVoice"},"assistant_message":"Ок","need_approval":false}'
        }
      }.to_json
    )
    post login_path, params: { email: @user.email, password: "password" }
    audio = Rack::Test::UploadedFile.new(StringIO.new("x"), "audio/webm", original_filename: "voice.webm")
    assert_difference("Lead.count", 1) do
      post voice_console_path, params: { audio: audio }
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert body["created_lead_id"].present?
  end

  test "POST to discarded lead returns 410 JSON without exception" do
    @lead.update!(discarded_at: Time.current)
    post login_path, params: { email: @user.email, password: "password" }
    audio = Rack::Test::UploadedFile.new(StringIO.new("x"), "audio/webm", original_filename: "voice.webm")
    post voice_lead_path(@lead), params: { audio: audio }
    assert_response :gone
    body = JSON.parse(response.body)
    assert_equal true, body["lead_gone"]
  end

  test "creates voice session and lead event" do
    post login_path, params: { email: @user.email, password: "password" }
    assert_response :redirect

    audio = Rack::Test::UploadedFile.new(StringIO.new("fake-audio"), "audio/webm", original_filename: "voice.webm")

    assert_difference([ "VoiceSession.count", "LeadEvent.count" ], 1) do
      post voice_lead_path(@lead), params: { audio: audio }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert body["success"]
    assert_includes body["transcript"].to_s, "проверка"
  end
end
