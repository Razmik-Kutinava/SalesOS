# frozen_string_literal: true

require "test_helper"

class FetchUrlsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "fetch-ui@test.dev")
    post login_path, params: { email: @user.email, password: "password" }

    @lead = create_lead!(@account, company_name: "UI Fetch Co.", source: "manual")

    @old_url = ENV["PLAYWRIGHT_FETCH_URL"]
    @old_hosts = ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"]
    @old_token = ENV["PLAYWRIGHT_FETCH_TOKEN"]

    ENV["PLAYWRIGHT_FETCH_URL"] = "http://127.0.0.1:3001"
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = "example.com"
    ENV.delete("PLAYWRIGHT_FETCH_TOKEN")
  end

  teardown do
    ENV["PLAYWRIGHT_FETCH_URL"] = @old_url
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = @old_hosts
    ENV["PLAYWRIGHT_FETCH_TOKEN"] = @old_token
  end

  test "POST creates lead event and redirects back to lead" do
    stub_request(:post, "http://127.0.0.1:3001/v1/fetch").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        ok: true,
        url: "https://example.com/",
        finalUrl: "https://example.com/",
        title: "Example Title",
        textContent: "hello from example.com",
        htmlSize: 123,
        statusCode: 200
      }.to_json
    )

    assert_difference("LeadEvent.where(lead_id: @lead.id, event_type: 'page_fetched').count", 1) do
      post lead_fetch_url_path(@lead), params: { url: "https://example.com/" }
    end

    follow_redirect!
    assert_response :success
    assert_match(/Example Title/i, response.body)
  end
end

