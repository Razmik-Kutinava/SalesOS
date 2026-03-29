# frozen_string_literal: true

require "test_helper"

class KnowledgeDocumentsTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "rag-uploader@test.dev")
    post login_path, params: { email: @user.email, password: "password" }
  end

  test "rejects non-pdf file" do
    post knowledge_documents_path, params: {
      file: Rack::Test::UploadedFile.new(StringIO.new("hello"), "text/plain", original_filename: "note.txt")
    }
    assert_redirected_to root_path
    assert_match(/PDF/i, flash[:alert].to_s)
  end

  test "create_from_text accepts long body and redirects" do
    assert_difference("KnowledgeDocument.count", 1) do
      post text_knowledge_documents_path, params: {
        body_text: "Достаточно длинная заметка для индекса в базе знаний.",
        title: "Из теста"
      }
    end
    assert_redirected_to root_path
    assert_match(/индексац/i, flash[:notice].to_s)
  end
end
