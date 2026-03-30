# frozen_string_literal: true

require "test_helper"

class Fetch::PlaywrightClientTest < ActiveSupport::TestCase
  setup do
    @base = "http://127.0.0.1:3001"
    @allow = "example.com,WWW.EXAMPLE.COM"
  end

  # --- 1–3: parse_allowed_hosts
  test "parse_allowed_hosts normalizes and dedupes case" do
    s = Fetch::PlaywrightClient.parse_allowed_hosts(" Example.COM , test.dev ")
    assert_equal Set.new(%w[example.com test.dev]), s
  end

  test "parse_allowed_hosts empty string yields empty set" do
    assert_predicate Fetch::PlaywrightClient.parse_allowed_hosts(""), :empty?
  end

  test "parse_allowed_hosts nil yields empty set" do
    assert_predicate Fetch::PlaywrightClient.parse_allowed_hosts(nil), :empty?
  end

  # --- 4–5: configured?
  test "configured? is false when base url blank" do
    c = Fetch::PlaywrightClient.new(base_url: "", allowed_hosts: "x.com")
    assert_not c.configured?
  end

  test "configured? is true when base url present" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "x.com")
    assert c.configured?
  end

  # --- 6–9: configuration and URL scheme
  test "fetch raises ConfigurationError when base url missing" do
    c = Fetch::PlaywrightClient.new(base_url: "", allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::ConfigurationError) do
      c.fetch(url: "https://example.com/")
    end
  end

  test "fetch rejects javascript URL scheme" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      c.fetch(url: "javascript:alert(1)")
    end
  end

  test "fetch rejects ftp scheme" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      c.fetch(url: "ftp://example.com/")
    end
  end

  test "fetch rejects empty allowlist" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "")
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      c.fetch(url: "https://example.com/")
    end
  end

  # --- 10–11: allowlist
  test "fetch rejects host not in allowlist" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "other.org")
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      c.fetch(url: "https://example.com/")
    end
  end

  test "fetch accepts host when allowlist matches" do
    stub_fetch_ok!(final_url: "https://example.com/")
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: @allow, token: "secret")
    r = c.fetch(url: "https://example.com/")
    assert_equal true, r["ok"]
    assert_equal "https://example.com/", r["finalUrl"]
  end

  # --- 12–15: HTTP / JSON
  test "fetch raises HttpError on worker 500" do
    stub_request(:post, "#{@base}/v1/fetch").to_return(status: 500, body: "oops")
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::HttpError) do
      c.fetch(url: "https://example.com/")
    end
  end

  test "fetch succeeds on JSON error body with HTTP 200" do
    stub_request(:post, "#{@base}/v1/fetch").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { ok: false, error: "timeout" }.to_json
    )
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    r = c.fetch(url: "https://example.com/")
    assert_equal false, r["ok"]
    assert_equal "timeout", r["error"]
  end

  test "fetch raises on invalid JSON with non-success HTTP" do
    stub_request(:post, "#{@base}/v1/fetch").to_return(status: 502, body: "not json")
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::HttpError) do
      c.fetch(url: "https://example.com/")
    end
  end

  test "fetch sends Authorization Bearer when token set" do
    stub_fetch_ok!
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com", token: "tok")
    c.fetch(url: "https://example.com/")
    assert_requested(:post, "#{@base}/v1/fetch", headers: { "Authorization" => "Bearer tok" })
  end

  # --- 16–19: JSON body shape
  test "fetch default waitUntil is load" do
    stub_fetch_ok!
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    c.fetch(url: "https://example.com/")
    assert_requested(:post, "#{@base}/v1/fetch") do |req|
      body = JSON.parse(req.body)
      body["waitUntil"] == "load"
    end
  end

  test "fetch passes domcontentloaded when requested" do
    stub_fetch_ok!
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    c.fetch(url: "https://example.com/", wait_until: "domcontentloaded")
    assert_requested(:post, "#{@base}/v1/fetch") do |req|
      JSON.parse(req.body)["waitUntil"] == "domcontentloaded"
    end
  end

  test "fetch passes timeout_ms when given" do
    stub_fetch_ok!
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    c.fetch(url: "https://example.com/", timeout_ms: 15_000)
    assert_requested(:post, "#{@base}/v1/fetch") do |req|
      JSON.parse(req.body)["timeout"] == 15_000
    end
  end

  test "fetch response includes title when worker returns ok" do
    stub_request(:post, "#{@base}/v1/fetch").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        ok: true,
        url: "https://example.com/",
        finalUrl: "https://example.com/",
        title: "Ex",
        textContent: "hello",
        htmlSize: 100,
        statusCode: 200
      }.to_json
    )
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    r = c.fetch(url: "https://example.com/")
    assert_equal "Ex", r["title"]
    assert_equal "hello", r["textContent"]
  end

  # --- 20–24: edge cases
  test "http URL allowed when in allowlist" do
    stub_fetch_ok!(final_url: "http://example.com/")
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    r = c.fetch(url: "http://example.com/")
    assert_equal true, r["ok"]
  end

  test "subdomain must match exactly not parent domain" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      c.fetch(url: "https://evil.example.com/")
    end
  end

  test "www host must be listed separately if needed" do
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com")
    assert_raises(Fetch::PlaywrightClient::NotAllowedError) do
      c.fetch(url: "https://www.example.com/")
    end
  end

  test "client uses https when base url is https" do
    stub_request(:post, "https://pw.example.com/v1/fetch").to_return(
      status: 200,
      body: { ok: true, url: "https://a.com", finalUrl: "https://a.com", title: "", textContent: "", htmlSize: 0, statusCode: 200 }.to_json
    )
    c = Fetch::PlaywrightClient.new(
      base_url: "https://pw.example.com",
      allowed_hosts: "a.com"
    )
    c.fetch(url: "https://a.com/")
    assert_requested(:post, "https://pw.example.com/v1/fetch")
  end

  test "open and read timeouts are passed to Net::HTTP via client" do
    stub_fetch_ok!
    c = Fetch::PlaywrightClient.new(
      base_url: @base,
      allowed_hosts: "example.com",
      open_timeout: 3,
      read_timeout: 7
    )
    c.fetch(url: "https://example.com/")
    assert_requested(:post, "#{@base}/v1/fetch")
  end

  test "fetch does not send Authorization when token blank" do
    stub_fetch_ok!
    c = Fetch::PlaywrightClient.new(base_url: @base, allowed_hosts: "example.com", token: "")
    c.fetch(url: "https://example.com/")
    assert_requested(:post, "#{@base}/v1/fetch") do |req|
      req.headers.transform_keys(&:downcase)["authorization"].nil?
    end
  end

  test "base url trailing slash is normalized" do
    stub_request(:post, "http://127.0.0.1:3009/v1/fetch").to_return(
      status: 200,
      body: { ok: true, url: "https://example.com/", finalUrl: "https://example.com/", title: "", textContent: "", htmlSize: 0, statusCode: 200 }.to_json
    )
    c = Fetch::PlaywrightClient.new(base_url: "http://127.0.0.1:3009/", allowed_hosts: "example.com")
    c.fetch(url: "https://example.com/")
    assert_requested(:post, "http://127.0.0.1:3009/v1/fetch")
  end

  private

  def stub_fetch_ok!(final_url: "https://example.com/")
    stub_request(:post, "#{@base}/v1/fetch").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        ok: true,
        url: "https://example.com/",
        finalUrl: final_url,
        title: "Example",
        textContent: "ok",
        htmlSize: 10,
        statusCode: 200
      }.to_json
    )
  end
end
