require "test_helper"

class VoiceSessionTest < ActiveSupport::TestCase
  test "rejects invalid status" do
    account = create_account!
    user = create_user!(account)
    session = VoiceSession.new(user: user, status: "sleeping")
    assert_not session.valid?
    assert session.errors.key?(:status)
  end

  test "lead is optional" do
    account = create_account!
    user = create_user!(account)
    session = VoiceSession.create!(user: user, status: "pending", lead: nil)
    assert_nil session.lead_id
  end

  test "persists with user and done status" do
    account = create_account!
    user = create_user!(account)
    lead = create_lead!(account)
    session = VoiceSession.create!(
      user: user,
      lead: lead,
      status: "done",
      transcript: "закрой сделку"
    )
    assert_predicate session.reload, :persisted?
    assert_equal "done", session.status
  end
end
