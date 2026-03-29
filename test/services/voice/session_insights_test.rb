# frozen_string_literal: true

require "test_helper"

class VoiceSessionInsightsTest < ActiveSupport::TestCase
  test "report aggregates status and intents" do
    account = create_account!
    user = create_user!(account)
    lead = create_lead!(account)

    VoiceSession.create!(
      user: user,
      lead: lead,
      status: "done",
      transcript: "a",
      raw_llm_response: { "intent" => "add_note" },
      created_at: 1.day.ago
    )
    VoiceSession.create!(
      user: user,
      lead: lead,
      status: "done",
      transcript: "b",
      raw_llm_response: { "intent" => "add_note" },
      created_at: 1.day.ago
    )
    VoiceSession.create!(
      user: user,
      lead: lead,
      status: "error",
      transcript: "c",
      error_message: "no_lead",
      created_at: 1.day.ago
    )

    r = Voice::SessionInsights.report(since: 2.days.ago)
    assert_equal 3, r[:total]
    assert_equal 2, r[:by_status]["done"]
    assert_equal 1, r[:by_status]["error"]
    assert_equal 2, r[:intent_histogram]["add_note"]
    assert r[:success_rate].is_a?(Float)
  end
end
