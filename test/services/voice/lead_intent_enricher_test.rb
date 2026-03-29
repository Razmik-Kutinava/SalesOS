# frozen_string_literal: true

require "test_helper"

class VoiceLeadIntentEnricherTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  test "promotes add_note to update_lead when email appears in transcript" do
    parsed = {
      "intent" => "add_note",
      "slots" => { "note" => "всё ок" },
      "assistant_message" => "Заметка сохранена",
      "need_approval" => false
    }
    tr = "Установи email client@example.com для этого лида"
    Voice::LeadIntentEnricher.apply!(parsed, tr)
    assert_equal "update_lead", parsed["intent"]
    assert_equal "client@example.com", parsed.dig("slots", "email")
  end

  test "promotes add_note when spoken собака domain" do
    parsed = {
      "intent" => "add_note",
      "slots" => { "note" => "запиши почту ivan собака mail.ru" },
      "assistant_message" => "Ок",
      "need_approval" => false
    }
    Voice::LeadIntentEnricher.apply!(parsed, "")
    assert_equal "update_lead", parsed["intent"]
    assert_equal "ivan@mail.ru", parsed.dig("slots", "email")
  end

  test "does not promote pure diary add_note without structured cues" do
    parsed = {
      "intent" => "add_note",
      "slots" => { "note" => "Клиент отложил решение на неделю" },
      "assistant_message" => "Ок",
      "need_approval" => false
    }
    Voice::LeadIntentEnricher.apply!(parsed, "Клиент отложил решение на неделю")
    assert_equal "add_note", parsed["intent"]
  end

  test "promotes noop to delete_lead on explicit удали лид phrase" do
    parsed = {
      "intent" => "noop",
      "slots" => {},
      "assistant_message" => "",
      "need_approval" => false
    }
    Voice::LeadIntentEnricher.apply!(parsed, "Пожалуйста удали этот лид")
    assert_equal "delete_lead", parsed["intent"]
  end

  test "promotes add_note to update_lead with next_call_at on weekday пятница in user timezone" do
    travel_to Time.find_zone("Europe/Moscow").parse("2026-03-25 12:00:00") do
      parsed = {
        "intent" => "add_note",
        "slots" => { "note" => "перенос" },
        "assistant_message" => "Ок",
        "need_approval" => false
      }
      tr = "Следующий звонок в пятницу в 11"
      Voice::LeadIntentEnricher.apply!(parsed, tr, timezone: "Europe/Moscow")
      assert_equal "update_lead", parsed["intent"]
      z = Time.find_zone("Europe/Moscow")
      t = z.parse(parsed.dig("slots", "next_call_at").to_s)
      assert_equal 27, t.day
      assert_equal 11, t.hour
    end
  end

  test "promotes add_note to update_lead with next_call_at from spoken завтра в час" do
    parsed = {
      "intent" => "add_note",
      "slots" => { "note" => "клиент просит перенос" },
      "assistant_message" => "Ок",
      "need_approval" => false
    }
    tr = "Перезвонить завтра в 15:30"
    Voice::LeadIntentEnricher.apply!(parsed, tr)
    assert_equal "update_lead", parsed["intent"]
    assert parsed.dig("slots", "next_call_at").present?
    assert_match(/\d{4}-\d{2}-\d{2}T15:30:00/, parsed.dig("slots", "next_call_at").to_s)
  end

  test "update_lead intent is unchanged by enricher" do
    parsed = {
      "intent" => "update_lead",
      "slots" => { "email" => "a@b.co" },
      "assistant_message" => "Ок",
      "need_approval" => false
    }
    Voice::LeadIntentEnricher.apply!(parsed, "x")
    assert_equal "update_lead", parsed["intent"]
  end
end
