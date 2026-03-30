# frozen_string_literal: true

require "test_helper"

class SearchQueriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "search-ui@test.dev")
    post login_path, params: { email: @user.email, password: "password" }

    @lead = create_lead!(@account, company_name: "Lead Co.", source: "manual")

    @old_serper_key = ENV["SERPER_API_KEY"]
    @old_tavily_key = ENV["TAVILY_API_KEY"]
    @old_brave_key = ENV["BRAVE_API_KEY"]

    @old_serper_url = ENV["SERPER_API_URL"]
    @old_tavily_url = ENV["TAVILY_API_URL"]
    @old_brave_url = ENV["BRAVE_API_URL"]

    ENV["SERPER_API_KEY"] = "x"
    ENV["TAVILY_API_KEY"] = "y"
    ENV["BRAVE_API_KEY"] = "z"

    # Упрощаем стабы: направляем клиентов на локальные фиктивные endpoints.
    ENV["SERPER_API_URL"] = "http://serper.test/search"
    ENV["TAVILY_API_URL"] = "http://tavily.test/search"
    ENV["BRAVE_API_URL"] = "http://brave.test/res/v1/web/search"

    @old_pw_url = ENV["PLAYWRIGHT_FETCH_URL"]
    @old_pw_hosts = ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"]
    @old_pw_token = ENV["PLAYWRIGHT_FETCH_TOKEN"]

    ENV["PLAYWRIGHT_FETCH_URL"] = "http://127.0.0.1:3001"
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = "example.com"
    ENV.delete("PLAYWRIGHT_FETCH_TOKEN")

    # В этом тесте Ollama — чистый WebMock.
    ENV["OLLAMA_HOST"] = "http://127.0.0.1:11434"
  end

  teardown do
    ENV["SERPER_API_KEY"] = @old_serper_key
    ENV["TAVILY_API_KEY"] = @old_tavily_key
    ENV["BRAVE_API_KEY"] = @old_brave_key

    ENV["SERPER_API_URL"] = @old_serper_url
    ENV["TAVILY_API_URL"] = @old_tavily_url
    ENV["BRAVE_API_URL"] = @old_brave_url

    ENV["PLAYWRIGHT_FETCH_URL"] = @old_pw_url
    ENV["PLAYWRIGHT_FETCH_ALLOWED_HOSTS"] = @old_pw_hosts
    if @old_pw_token.present?
      ENV["PLAYWRIGHT_FETCH_TOKEN"] = @old_pw_token
    else
      ENV.delete("PLAYWRIGHT_FETCH_TOKEN")
    end

    ENV["OLLAMA_HOST"] = nil
  end

  test "POST /leads/:id/search: 3 провайдера -> Ollama select -> Playwright fetch -> Ollama approve" do
    # 1) Поиск: Serper + Tavily + Brave возвращают одинаковую сущность на разных URL.
    stub_request(:post, "http://serper.test/search").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        "organic" => [
          { "title" => "Example Careers", "link" => "https://example.com/careers", "snippet" => "Careers page" }
        ]
      }.to_json
    )

    stub_request(:post, "http://tavily.test/search").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        "results" => [
          { "url" => "https://example.com/careers", "title" => "Example Careers", "content" => "Open roles at Example" }
        ]
      }.to_json
    )

    stub_request(:post, "http://brave.test/res/v1/web/search").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        "web" => {
          "results" => [
            { "url" => "https://example.com/careers", "title" => "Example Careers", "description" => "Jobs and vacancies" }
          ]
        }
      }.to_json
    )

    # 2) Ollama (шаг select): выбирает один URL для Playwright.
    # WebMock: два подряд вызова /api/chat — сначала select, потом verify.
    ollama_chat = "http://127.0.0.1:11434/api/chat"

    stub_request(:post, ollama_chat).to_return([
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "message" => {
            "role" => "assistant",
            "content" => {
              candidate_urls: [
                {
                  url: "https://example.com/careers",
                  reason: "Похоже на нужную страницу с вакансиями",
                  confidence: 0.9,
                  needs_playwright_confirmation: true
                }
              ],
              needs_manual_review: false,
              selection_reason: "URL выбран по title/snippet"
            }.to_json
          }
        }.to_json
      },
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "message" => {
            "role" => "assistant",
            "content" => {
              approved_sources: [
                {
                  url: "https://example.com/careers",
                  reason: "На странице подтверждается релевантность",
                  confidence: 0.87,
                  extracted_fields: {
                    company_name: "Example Co",
                    email: "info@example.com",
                    phone: "+1234567",
                    contact_name: "Ivan",
                    stage: "qualified"
                  }
                }
              ],
              rejected_sources: [],
              lead_updates: {
                company_name: "Example Co",
                email: "info@example.com",
                phone: "+1234567",
                contact_name: "Ivan",
                stage: "qualified"
              },
              needs_manual_review: false,
              verification_reason: "Факты совпадают с запросом"
            }.to_json
          }
        }.to_json
      }
    ])

    # 3) Parser (Playwright): Fetch::PlaywrightClient вызывает worker /v1/fetch.
    stub_request(:post, "http://127.0.0.1:3001/v1/fetch").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: {
        ok: true,
        url: "https://example.com/careers",
        finalUrl: "https://example.com/careers",
        title: "Example Careers",
        textContent: "Example Corp is hiring. Contact: Ivan. Email: info@example.com. Phone: +1234567",
        htmlSize: 123,
        statusCode: 200
      }.to_json
    )

    assert_difference("LeadEvent.where(lead_id: @lead.id, event_type: 'search_approved').count", 1) do
      post lead_search_path(@lead), params: { query: "Example careers vacancies" }
    end

    follow_redirect!
    assert_response :success
    assert_match(/Одобрено источников/i, response.body)
    assert_match(/example.com\/careers/i, response.body)

    @lead.reload
    assert_equal "Example Co", @lead.company_name
    assert_equal "Ivan", @lead.contact_name
    assert_equal "info@example.com", @lead.email
    assert_equal "+1234567", @lead.phone
    assert_equal "qualified", @lead.stage
  end

  test "не одобряем источник: loopback/unsafe хост блокируется в Rails fetch" do
    ollama_chat = "http://127.0.0.1:11434/api/chat"
    unsafe_url = "http://127.0.0.1:8000/page"

    stub_request(:post, "http://serper.test/search").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { "organic" => [ { "title" => "Unsafe", "link" => unsafe_url, "snippet" => "..." } ] }.to_json
    )
    stub_request(:post, "http://tavily.test/search").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { "results" => [ { "url" => unsafe_url, "title" => "Unsafe", "content" => "..." } ] }.to_json
    )
    stub_request(:post, "http://brave.test/res/v1/web/search").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { "web" => { "results" => [ { "url" => unsafe_url, "title" => "Unsafe", "description" => "..." } ] } }.to_json
    )

    stub_request(:post, ollama_chat).to_return([
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "message" => {
            "role" => "assistant",
            "content" => {
              candidate_urls: [
                { url: unsafe_url, reason: "нужная страница", confidence: 0.8, needs_playwright_confirmation: true }
              ],
              needs_manual_review: false,
              selection_reason: "выбрано по сниппету"
            }.to_json
          }
        }.to_json
      },
      {
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "message" => {
            "role" => "assistant",
            "content" => {
              approved_sources: [],
              rejected_sources: [],
              lead_updates: {},
              needs_manual_review: true,
              verification_reason: "unsafe_host"
            }.to_json
          }
        }.to_json
      }
    ])

    # Важно: мы НЕ стабуем /v1/fetch, потому что Rails клиент блокирует unsafe хост до HTTP.

    assert_difference("LeadEvent.where(lead_id: @lead.id, event_type: 'search_approved').count", 1) do
      post lead_search_path(@lead), params: { query: "Unsafe vacancies" }
    end

    follow_redirect!
    assert_response :success
    assert_match(/Нужен/ix, response.body)
  end
end

