# frozen_string_literal: true

require "test_helper"

class Imports::LeadImportProcessorTest < ActiveSupport::TestCase
  setup do
    @account = create_account!
    @user = create_user!(@account)
    @import = @account.lead_imports.new(user: @user, status: "queued", column_mapping: {}, preview_headers: [])
    @import.file.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample_leads.csv")),
      filename: "sample_leads.csv",
      content_type: "text/csv"
    )
    @import.save!
    @import.update!(
      preview_headers: [ "Company Name", "Contact", "Email", "Phone" ],
      column_mapping: Imports::ColumnMapper.heuristic([ "Company Name", "Contact", "Email", "Phone" ])
    )
  end

  test "creates leads and lead_imported events" do
    assert_difference("Lead.count", 2) do
      assert_difference("LeadEvent.where(event_type: 'lead_imported').count", 2) do
        Imports::LeadImportProcessor.call(@import)
      end
    end

    @import.reload
    assert_equal "completed", @import.status
    assert_equal 2, @import.result_summary["created"]
  end
end
