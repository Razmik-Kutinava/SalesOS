require "test_helper"

class LeadTest < ActiveSupport::TestCase
  test "rejects invalid stage" do
    account = create_account!
    lead = create_lead!(account)
    lead.stage = "bogus"
    assert_not lead.valid?
    assert lead.errors.key?(:stage)
  end

  test "rejects invalid source" do
    account = create_account!
    lead = create_lead!(account)
    lead.source = "unknown"
    assert_not lead.valid?
    assert lead.errors.key?(:source)
  end

  test "rejects score above 100" do
    account = create_account!
    lead = create_lead!(account, score: 100)
    lead.score = 101
    assert_not lead.valid?
    assert lead.errors.key?(:score)
  end

  test "rejects negative score" do
    account = create_account!
    lead = build_lead(account, score: -1)
    assert_not lead.valid?
    assert lead.errors.key?(:score)
  end

  test "kept scope excludes discarded leads" do
    account = create_account!
    active = create_lead!(account, company_name: "Active")
    discarded = create_lead!(account, company_name: "Gone", discarded_at: Time.current)
    kept = Lead.kept.where(account_id: account.id)
    assert_includes kept, active
    assert_not_includes kept, discarded
  end

  test "owner is optional" do
    account = create_account!
    lead = create_lead!(account, owner: nil)
    assert_nil lead.owner_id
    assert_predicate lead, :valid?
  end

  private

  def build_lead(account, attrs = {})
    Lead.new({ account: account, company_name: "B" }.merge(attrs))
  end
end
