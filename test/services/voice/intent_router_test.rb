# frozen_string_literal: true

require "test_helper"

# Поведение «что можно сказать голосом» (после Whisper/Ollama) фиксируется интентами IntentRouter.
class VoiceIntentRouterTest < ActiveSupport::TestCase
  setup do
    @account = create_account!
    @user = create_user!(@account, role: "owner")
    @lead = create_lead!(@account)
    @router = Voice::IntentRouter.new(user: @user, lead: @lead)
    @router_no_lead = Voice::IntentRouter.new(user: @user, lead: nil)
  end

  # --- create_lead ---
  test "without lead only create_lead noop and add_knowledge succeed" do
    ok = @router_no_lead.call({ "intent" => "create_lead", "slots" => { "company_name" => "Solo" }, "assistant_message" => "Ок" })
    assert ok.success
    assert_equal "lead:create", ok.applied.first

    bad = @router_no_lead.call({ "intent" => "add_note", "slots" => { "note" => "x" }, "assistant_message" => "?" })
    assert_not bad.success
  end

  test "add_knowledge without lead creates text document and enqueues index job" do
    text = "Достаточно длинный текст для сохранения в базе знаний."
    assert_difference("KnowledgeDocument.count", 1) do
      assert_enqueued_jobs 1, only: IndexKnowledgeDocumentJob do
        r = @router_no_lead.call({
          "intent" => "add_knowledge",
          "slots" => { "content" => text, "title" => "Голосовая заметка" },
          "assistant_message" => "Сохранил"
        })
        assert r.success
        assert_includes r.applied, "knowledge:add_text"
      end
    end
    doc = KnowledgeDocument.last
    assert_equal text, doc.body_text
    assert_equal "Голосовая заметка", doc.title
  end

  test "add_knowledge with lead creates lead_event" do
    text = "Ещё один достаточно длинный текст для индексации в базе."
    assert_difference([ "KnowledgeDocument.count", "LeadEvent.count" ], 1) do
      r = @router.call({
        "intent" => "add_knowledge",
        "slots" => { "content" => text },
        "assistant_message" => "Ок"
      })
      assert r.success
    end
    assert_equal "knowledge_snippet_voice", LeadEvent.last.event_type
    assert_equal KnowledgeDocument.last.id, LeadEvent.last.payload["knowledge_document_id"]
  end

  test "add_knowledge rejects short content" do
    r = @router.call({ "intent" => "add_knowledge", "slots" => { "content" => "коротко" }, "assistant_message" => "?" })
    assert_not r.success
  end

  test "create_lead adds new lead and returns created_lead_id" do
    assert_difference("Lead.count", 1) do
      r = @router.call({
        "intent" => "create_lead",
        "slots" => { "company_name" => "VoiceCo", "contact_name" => "Ann" },
        "assistant_message" => "Создал"
      })
      assert r.success
      assert_equal "lead:create", r.applied.first
      assert_equal Lead.last.id, r.created_lead_id
    end
    assert_equal "voice", Lead.last.source
  end

  # --- noop ---
  test "noop marks success and records noop action" do
    r = @router.call({ "intent" => "noop", "assistant_message" => "Привет" })
    assert r.success
    assert_equal [ "noop" ], r.applied
    assert_equal "Привет", r.assistant_message
  end

  test "noop uses default assistant text when blank" do
    r = @router.call({ "intent" => "noop" })
    assert r.success
    assert_equal "Готово.", r.assistant_message
  end

  # --- unknown ---
  test "unknown intent fails with safe message" do
    r = @router.call({ "intent" => "drop_database", "assistant_message" => "x" })
    assert_not r.success
    assert_equal "Неизвестное намерение.", r.assistant_message
  end

  # --- add_note (голос: «добавь заметку …») ---
  test "add_note creates voice_note lead_event" do
    assert_difference("LeadEvent.count", 1) do
      r = @router.call({ "intent" => "add_note", "slots" => { "note" => "Звонок" }, "assistant_message" => "Ок" })
      assert r.success
    end
    ev = LeadEvent.last
    assert_equal "voice_note", ev.event_type
    assert_equal "Звонок", ev.payload["body"]
    assert_equal @user, ev.actor
  end

  test "add_note rejects empty note" do
    r = @router.call({ "intent" => "add_note", "slots" => { "note" => "   " }, "assistant_message" => "?" })
    assert_not r.success
    assert_match(/Пустая заметка/, r.error_message.to_s)
  end

  test "add_note rejects missing note" do
    r = @router.call({ "intent" => "add_note", "slots" => {}, "assistant_message" => "?" })
    assert_not r.success
  end

  # --- update_lead (голос: «поменяй компанию на …», «перенеси следующий звонок на …») ---
  test "update_lead changes company_name and email" do
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "company_name" => "NewCo", "email" => "a@b.co" },
      "assistant_message" => "Обновил"
    })
    assert r.success
    @lead.reload
    assert_equal "NewCo", @lead.company_name
    assert_equal "a@b.co", @lead.email
    assert_equal "lead_updated", LeadEvent.last.event_type
  end

  test "update_lead sets next_call_at from ISO8601" do
    iso = "2026-05-15T14:30:00Z"
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "next_call_at" => iso },
      "assistant_message" => "Перенёс звонок"
    })
    assert r.success
    assert_equal Time.zone.parse(iso), @lead.reload.next_call_at
    assert_includes LeadEvent.last.payload["fields"], "next_call_at"
  end

  test "update_lead combines text fields and next_call_at" do
    iso = "2026-06-01T09:00:00Z"
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "phone" => "+79990001122", "next_call_at" => iso },
      "assistant_message" => "Ок"
    })
    assert r.success
    @lead.reload
    assert_equal "+79990001122", @lead.phone
    assert_equal Time.zone.parse(iso), @lead.next_call_at
  end

  test "update_lead sets stage when value is in Lead::STAGES" do
    assert_not_equal "won", @lead.stage
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "stage" => "won", "company_name" => "SafeCo" },
      "assistant_message" => "Ок"
    })
    assert r.success
    @lead.reload
    assert_equal "SafeCo", @lead.company_name
    assert_equal "won", @lead.stage
  end

  test "update_lead ignores invalid stage string" do
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "stage" => "not_a_real_stage" },
      "assistant_message" => "?"
    })
    assert_not r.success
  end

  test "update_lead sets score in 0..100" do
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "score" => 42 },
      "assistant_message" => "Ок"
    })
    assert r.success
    assert_equal 42, @lead.reload.score
  end

  test "update_lead fails when only invalid next_call_at and no text fields" do
    r = @router.call({
      "intent" => "update_lead",
      "slots" => { "next_call_at" => "not-a-date" },
      "assistant_message" => "?"
    })
    assert_not r.success
    assert_match(/Нет полей/, r.error_message.to_s)
  end

  test "update_lead fails when slots empty" do
    r = @router.call({ "intent" => "update_lead", "slots" => {}, "assistant_message" => "?" })
    assert_not r.success
  end

  # --- create_task (голос: «поставь задачу … на завтра») ---
  test "create_task creates open task for user" do
    assert_difference([ "Task.count", "LeadEvent.count" ], 1) do
      r = @router.call({
        "intent" => "create_task",
        "slots" => { "title" => "Перезвонить" },
        "assistant_message" => "Задача создана"
      })
      assert r.success
    end
    t = Task.last
    assert_equal "Перезвонить", t.title
    assert_equal @user, t.assignee
    assert_equal "open", t.status
  end

  test "create_task sets due_at when parsable" do
    due = "2026-07-20T12:00:00Z"
    assert_difference("LeadEvent.count", 1) do
      @router.call({
        "intent" => "create_task",
        "slots" => { "title" => "Демо", "due_at" => due },
        "assistant_message" => "Ок"
      })
    end
    assert_equal Time.zone.parse(due), Task.last.due_at
  end

  test "create_task skips invalid due_at but still creates task" do
    assert_difference("LeadEvent.count", 1) do
      @router.call({
        "intent" => "create_task",
        "slots" => { "title" => "Без даты", "due_at" => "bogus" },
        "assistant_message" => "Ок"
      })
    end
    assert_nil Task.last.due_at
  end

  test "create_task rejects empty title" do
    r = @router.call({ "intent" => "create_task", "slots" => { "title" => "" }, "assistant_message" => "?" })
    assert_not r.success
  end

  # --- delete_lead (голос: «удали этот лид» → сразу discarded_at) ---
  test "delete_lead soft-deletes lead and records lead_discarded event" do
    assert_difference("LeadEvent.count", 1) do
      r = @router.call({
        "intent" => "delete_lead",
        "slots" => {},
        "assistant_message" => "Удалил"
      })
      assert r.success
      assert_includes r.applied, "lead:discarded"
    end
    assert_not_nil @lead.reload.discarded_at
    assert_equal "lead_discarded", LeadEvent.last.event_type
  end

  test "request_delete_lead intent is treated as immediate delete_lead" do
    r = @router.call({
      "intent" => "request_delete_lead",
      "slots" => {},
      "assistant_message" => "Ок"
    })
    assert r.success
    assert_includes r.applied, "lead:discarded"
    assert_not_nil @lead.reload.discarded_at
  end

  test "delete_lead fails if lead already discarded" do
    @lead.update!(discarded_at: Time.current)
    r = @router.call({ "intent" => "delete_lead", "assistant_message" => "?" })
    assert_not r.success
  end

  # --- slots typing ---
  test "symbol keys in slots are accepted via stringify" do
    r = @router.call({ "intent" => "add_note", "slots" => { note: "Символы" }, "assistant_message" => "x" })
    assert r.success
    assert_equal "Символы", LeadEvent.last.payload["body"]
  end
end
