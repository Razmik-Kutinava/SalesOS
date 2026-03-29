require "test_helper"

class LeadEventTest < ActiveSupport::TestCase
  test "requires event_type" do
    account = create_account!
    lead = create_lead!(account)
    event = LeadEvent.new(lead: lead, event_type: "", payload: {})
    assert_not event.valid?
    assert event.errors.key?(:event_type)
  end

  test "can attach polymorphic actor User" do
    account = create_account!
    user = create_user!(account)
    lead = create_lead!(account)
    event = LeadEvent.create!(
      lead: lead,
      actor: user,
      event_type: "note_added",
      payload: { "body" => "hello" }
    )
    assert_equal user, event.reload.actor
  end

  test "actor may be nil for system events" do
    account = create_account!
    lead = create_lead!(account)
    event = LeadEvent.create!(
      lead: lead,
      actor: nil,
      event_type: "imported",
      payload: {}
    )
    assert_nil event.reload.actor
  end
end
