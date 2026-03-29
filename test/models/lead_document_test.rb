require "test_helper"

class LeadDocumentTest < ActiveSupport::TestCase
  test "requires name" do
    account = create_account!
    lead = create_lead!(account)
    doc = LeadDocument.new(lead: lead, name: "", kind: "contract")
    assert_not doc.valid?
    assert doc.errors.key?(:name)
  end

  test "belongs to lead" do
    account = create_account!
    lead = create_lead!(account)
    doc = LeadDocument.create!(lead: lead, name: "MSA.pdf", kind: "contract")
    assert_equal lead, doc.reload.lead
  end
end
