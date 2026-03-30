# frozen_string_literal: true

require "test_helper"

class FetchUrlJobTest < ActiveJob::TestCase
  setup do
    @base = "http://127.0.0.1:3010"
    @old_url = ENV["PLAYWRIGHT_FETCH_URL"]
    @old_hosts = ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"]
    @old_token = ENV["PLAYWRIGHT_FETCH_TOKEN"]

    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "fetch-job@test.dev")
    @lead = create_lead!(@account, company_name: "Fetch Inc", source: "manual")
  end

  teardown do
    ENV["PLAYWRIGHT_FETCH_URL"] = @old_url
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = @old_hosts
    ENV["PLAYWRIGHT_FETCH_TOKEN"] = @old_token
  end

  test "perform returns early when worker URL not configured" do
    ENV.delete("PLAYWRIGHT_FETCH_URL")
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = "example.com"
    assert_raises(Fetch::PlaywrightClient::ConfigurationError) do
      FetchUrlJob.perform_now(@lead.id, "https://example.com/", actor_user_id: @user.id)
    end
  end

  test "perform calls worker and returns parsed JSON" do
    ENV["PLAYWRIGHT_FETCH_URL"] = @base
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = "example.com"
    ENV.delete("PLAYWRIGHT_FETCH_TOKEN")
    stub_request(:post, "#{@base}/v1/fetch").to_return(
      status: 200,
      body: { ok: true, url: "https://example.com/", finalUrl: "https://example.com/", title: "T", textContent: "x", htmlSize: 1, statusCode: 200 }.to_json
    )
    out = FetchUrlJob.perform_now(@lead.id, "https://example.com/", actor_user_id: @user.id)
    assert_equal true, out["ok"]
    assert_equal "T", out["title"]

    ev = @lead.lead_events.order(:id).last
    assert_equal "page_fetched", ev.event_type
    assert_equal "T", ev.payload["title"]
  end

  test "perform raises NotAllowedError when host blocked by client" do
    ENV["PLAYWRIGHT_FETCH_URL"] = @base
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = "good.com"
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      FetchUrlJob.perform_now(@lead.id, "https://bad.com/", actor_user_id: @user.id)
    end

    ev = @lead.lead_events.order(:id).last
    assert_equal "page_fetched", ev.event_type
    assert_equal false, ev.payload["ok"]
    assert ev.payload["error"].present?
  end

  test "perform raises HttpError when worker returns 500" do
    ENV["PLAYWRIGHT_FETCH_URL"] = @base
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = "example.com"
    stub_request(:post, "#{@base}/v1/fetch").to_return(status: 500, body: "err")
    assert_raises(Fetch::PlaywrightClient::HttpError) do
      FetchUrlJob.perform_now(@lead.id, "https://example.com/", actor_user_id: @user.id)
    end

    ev = @lead.lead_events.order(:id).last
    assert_equal "page_fetched", ev.event_type
    assert_equal false, ev.payload["ok"]
    assert ev.payload["error"].present?
  end
end
