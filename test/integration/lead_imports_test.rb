# frozen_string_literal: true

require "test_helper"

class LeadImportsTest < ActionDispatch::IntegrationTest
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner", email: "import-user@test.dev")
    post login_path, params: { email: @user.email, password: "password" }
  end

  test "upload csv creates leads and completes import job" do
    assert_difference("LeadImport.count", 1) do
      post lead_imports_path, params: {
        lead_import: {
          file: fixture_file_upload("sample_leads.csv", "text/csv"),
          use_llm_mapping: "0"
        }
      }
    end

    assert_response :redirect
    import = LeadImport.order(:id).last
    assert import.file.attached?

    perform_enqueued_jobs only: ProcessLeadImportJob

    import.reload
    assert_equal "completed", import.status
    assert_equal 2, import.result_summary["created"]
    assert_equal "import", Lead.order(:id).last(2).map(&:source).uniq.first

    get lead_import_path(import)
    assert_response :success
    assert_match(/Импорт/, response.body)
  end

  test "import tab renders on console" do
    get root_path(tab: "import")
    assert_response :success
    assert_match(/Импорт лидов/, response.body)
  end
end
