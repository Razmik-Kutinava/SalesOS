require "test_helper"

class PendingActionTest < ActiveSupport::TestCase
  test "rejects invalid status" do
    account = create_account!
    user = create_user!(account)
    lead = create_lead!(account)
    pa = PendingAction.new(
      user: user,
      lead: lead,
      action_type: "delete_lead",
      status: "unknown"
    )
    assert_not pa.valid?
    assert pa.errors.key?(:status)
  end

  test "requires action_type" do
    account = create_account!
    user = create_user!(account)
    lead = create_lead!(account)
    pa = PendingAction.new(user: user, lead: lead, action_type: "", status: "pending")
    assert_not pa.valid?
    assert pa.errors.key?(:action_type)
  end

  test "links user and lead" do
    account = create_account!
    user = create_user!(account)
    lead = create_lead!(account)
    pa = PendingAction.create!(
      user: user,
      lead: lead,
      action_type: "bulk_email",
      payload: { "ids" => [ lead.id ] },
      status: "pending"
    )
    assert_equal user, pa.reload.user
    assert_equal lead, pa.lead
  end
end
