# frozen_string_literal: true

require "test_helper"

class KnowledgeQueriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "rag-q@test.dev")
    post login_path, params: { email: @user.email, password: "password" }

    host = ENV.fetch("OLLAMA_HOST", "http://127.0.0.1:11434").chomp("/")
    stub_request(:post, "#{host}/api/embeddings")
      .to_return(status: 200, body: '{"embedding":[1.0,0.0,0.0]}', headers: { "Content-Type" => "application/json" })
  end

  test "create returns json when no indexed chunks" do
    post knowledge_query_path, params: { question: "что по скидке?" }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["grounded"]
    assert body["answer"].present?
  end
end
