# frozen_string_literal: true

module Voice
  # Allow-list интентов → изменения в БД (см. ADR 003).
  class IntentRouter
    Result = Data.define(:success, :assistant_message, :applied, :pending_action, :error_message, :created_lead_id)

    ALLOWED_INTENTS = %w[noop add_note update_lead create_task delete_lead request_delete_lead create_lead add_knowledge].freeze

    TEXT_LEAD_FIELDS = %w[company_name contact_name email phone].freeze

    def initialize(user:, lead:)
      @user = user
      @lead = lead
    end

    def call(parsed)
      intent = parsed["intent"].to_s.strip
      assistant = parsed["assistant_message"].to_s.presence || "Готово."
      slots = parsed["slots"].is_a?(Hash) ? parsed["slots"].stringify_keys : {}

      unless ALLOWED_INTENTS.include?(intent)
        return r(success: false, assistant_message: "Неизвестное намерение.", applied: [], error_message: intent)
      end

      intent = "delete_lead" if intent == "request_delete_lead"

      if @lead.nil?
        return call_without_selected_lead(intent, slots, assistant, parsed)
      end

      call_with_selected_lead(intent, slots, assistant, parsed)
    rescue ActiveRecord::RecordInvalid => e
      r(success: false, assistant_message: parsed["assistant_message"].to_s.presence || "Ошибка.", applied: [], error_message: e.message)
    end

    private

    def r(success:, assistant_message:, applied:, error_message: nil, created_lead_id: nil)
      Result.new(
        success: success,
        assistant_message: assistant_message,
        applied: applied,
        pending_action: nil,
        error_message: error_message,
        created_lead_id: created_lead_id
      )
    end

    def call_without_selected_lead(intent, slots, assistant, parsed)
      case intent
      when "noop"
        r(success: true, assistant_message: assistant, applied: [ "noop" ])
      when "create_lead"
        apply_create_lead(slots, assistant)
      when "add_knowledge"
        apply_add_knowledge(slots, assistant)
      else
        r(
          success: false,
          assistant_message: "Нет активного лида в таблице. Скажи: «создай лид, компания …» или выполни seed и выбери лид.",
          applied: [],
          error_message: "no_lead"
        )
      end
    end

    def call_with_selected_lead(intent, slots, assistant, parsed)
      case intent
      when "noop"
        r(success: true, assistant_message: assistant, applied: [ "noop" ])
      when "create_lead"
        apply_create_lead(slots, assistant)
      when "add_note"
        apply_add_note(slots, assistant)
      when "update_lead"
        apply_update_lead(slots, assistant)
      when "create_task"
        apply_create_task(slots, assistant)
      when "delete_lead"
        apply_delete_lead(assistant)
      when "add_knowledge"
        apply_add_knowledge(slots, assistant)
      end
    end

    def apply_create_lead(slots, assistant)
      company = slots["company_name"].to_s.strip.presence
      company ||= slots["title"].to_s.strip.presence # иногда модель кладёт в title
      company ||= "Новый лид"

      attrs = {
        company_name: company,
        contact_name: slots["contact_name"].to_s.strip.presence,
        email: slots["email"].to_s.strip.presence,
        phone: slots["phone"].to_s.strip.presence,
        stage: "new",
        source: "voice",
        score: 0,
        owner: @user,
        account: @user.account
      }

      st = slots["stage"].to_s.strip
      attrs[:stage] = st if st.present? && Lead::STAGES.include?(st)

      if slots.key?("score")
        sc = Integer(slots["score"]) rescue nil
        attrs[:score] = sc if sc && sc >= 0 && sc <= 100
      end

      lead = @user.account.leads.create!(attrs)
      LeadEvent.create!(
        lead: lead,
        actor: @user,
        event_type: "lead_created_voice",
        payload: { "source" => "voice" }
      )
      msg = assistant.presence || "Создан новый лид."
      r(success: true, assistant_message: msg, applied: [ "lead:create" ], created_lead_id: lead.id)
    end

    def apply_add_note(slots, assistant)
      note = slots["note"].to_s.strip
      if note.blank?
        return r(success: false, assistant_message: assistant, applied: [], error_message: "Пустая заметка")
      end

      LeadEvent.create!(
        lead: @lead,
        actor: @user,
        event_type: "voice_note",
        payload: { "body" => note }
      )
      r(success: true, assistant_message: assistant, applied: [ "lead_event:voice_note" ])
    end

    def apply_update_lead(slots, assistant)
      attrs = {}
      TEXT_LEAD_FIELDS.each do |key|
        v = slots[key].to_s.strip
        attrs[key] = v if v.present?
      end

      st = slots["stage"].to_s.strip
      attrs["stage"] = st if st.present? && Lead::STAGES.include?(st)

      if slots.key?("score")
        sc = Integer(slots["score"]) rescue nil
        attrs["score"] = sc if sc && sc >= 0 && sc <= 100
      end

      if slots["next_call_at"].present?
        t = parse_due(slots["next_call_at"])
        attrs["next_call_at"] = t if t
      end

      if attrs.empty?
        return r(success: false, assistant_message: assistant, applied: [], error_message: "Нет полей для обновления")
      end

      @lead.update!(attrs)
      LeadEvent.create!(
        lead: @lead,
        actor: @user,
        event_type: "lead_updated",
        payload: { "fields" => attrs.keys }
      )
      r(success: true, assistant_message: assistant, applied: [ "lead:update" ])
    end

    def apply_create_task(slots, assistant)
      title = slots["title"].to_s.strip
      if title.blank?
        return r(success: false, assistant_message: assistant, applied: [], error_message: "Пустой заголовок задачи")
      end

      due = parse_due(slots["due_at"])
      task = Task.create!(
        lead: @lead,
        assignee: @user,
        title: title,
        due_at: due,
        status: "open"
      )
      LeadEvent.create!(
        lead: @lead,
        actor: @user,
        event_type: "task_created",
        payload: { "task_id" => task.id, "title" => title }
      )
      r(success: true, assistant_message: assistant, applied: [ "task:create" ])
    end

    def apply_add_knowledge(slots, assistant)
      content = slots["content"].to_s.strip.presence || slots["note"].to_s.strip
      if content.blank? || content.length < KnowledgeDocument::MIN_BODY_TEXT
        return r(success: false, assistant_message: assistant, applied: [], error_message: "Слишком короткий текст для базы знаний")
      end

      if content.length > KnowledgeDocument::MAX_BODY_TEXT
        return r(success: false, assistant_message: assistant, applied: [], error_message: "Текст слишком длинный")
      end

      title = slots["title"].to_s.strip.presence || "Голос #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
      doc = @user.account.knowledge_documents.create!(
        title: title,
        body_text: content,
        status: "pending"
      )
      IndexKnowledgeDocumentJob.perform_later(doc.id)

      if @lead
        LeadEvent.create!(
          lead: @lead,
          actor: @user,
          event_type: "knowledge_snippet_voice",
          payload: { "knowledge_document_id" => doc.id }
        )
      end

      msg = assistant.presence || "Текст добавлен в базу знаний, идёт индексация."
      r(success: true, assistant_message: msg, applied: [ "knowledge:add_text" ])
    end

    def apply_delete_lead(assistant)
      if @lead.discarded_at.present?
        return r(success: false, assistant_message: assistant, applied: [], error_message: "Лид уже удалён")
      end

      LeadEvent.create!(
        lead: @lead,
        actor: @user,
        event_type: "lead_discarded",
        payload: { "reason" => "voice" }
      )
      @lead.update!(discarded_at: Time.current)
      msg = assistant.presence || "Лид удалён из активных."
      r(success: true, assistant_message: msg, applied: [ "lead:discarded" ])
    end

    def parse_due(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
