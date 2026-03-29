# frozen_string_literal: true

require "json"

module Voice
  # Транскрипт + контекст лида → JSON с intent/slots (Ollama, format json).
  class OllamaIntentParser
    SCHEMA_RULES = <<~PROMPT
      Ответь ТОЛЬКО одним JSON-объектом без markdown.

      Приоритет выбора intent (важно):
      1) delete_lead — ТОЛЬКО при явной команде убрать ЭТОТ лид: «удали лид», «убери контакт», «закрой лид». Не путать с субтитрами/мусором в транскрипте.
      2) create_lead — «создай лид», «новый лид», «добавь компанию …» (company_name обязательно осмысленное имя; если в речи только мусор — noop).
      3) update_lead — изменить карточку: контакт, компанию, email, телефон, этап, скоринг, следующий звонок.
      4) create_task — задача, напоминание.
      5) add_note — только заметка в лид без правок полей и без базы знаний.
      6) add_knowledge — «добавь в базу знаний», «запомни для всех», «сохрани в базу: …» — текст в slots.content (не короче 10 символов смысла); опционально slots.title.
      7) noop — непонятно.

      Если в контексте указано «лид не выбран» / нет id — для команд про новую компанию используй create_lead, не delete_lead.

      Поля JSON:
      - "intent": noop | add_note | update_lead | create_task | delete_lead | create_lead | add_knowledge
      - "slots":
        • add_note: "note".
        • add_knowledge: "content" (обязательно, полный текст для базы знаний), опционально "title".
        • update_lead: company_name, contact_name, email, phone, stage, score, next_call_at.
        • create_task: "title", опционально "due_at" (ISO8601).
        • create_lead: company_name (обязательно), contact_name, email, phone, stage, score — что успел разобрать из речи.
        • delete_lead: {}.
      - "assistant_message": одно короткое предложение по-русски, что сделано.
      - "need_approval": false (для голоса удаление выполняется сразу по явной команде).
    PROMPT

    # Few-shot: граничные и типовые фразы (без «лучших» — только разнообразие формулировок).
    FEW_SHOT_EXAMPLES = <<~PROMPT
      Примеры (речь → ожидаемый intent в JSON):
      - «Создай лид, компания Ромашка, контакт Петр» → create_lead.
      - «Удали этот лид» / «убери контакт из активных» → delete_lead (не delete при фразе «удали заметку»).
      - «Поставь email ivan@test.ru» / «иван собака mail.ru» → update_lead.
      - «Перезвонить завтра в 15:30» / «следующий звонок в пятницу в 11» → update_lead, slots.next_call_at по возможности.
      - «Задача: отправить КП» → create_task.
      - «Коротко: клиент просит счёт» → add_note.
      - «Добавь в базу знаний: скидка по акции 10 процентов до конца месяца» → add_knowledge, slots.content с полным текстом.
      - «Субтитры: спасибо за просмотр» / неразборчивый шум → noop (не delete_lead).
    PROMPT

    RETRY_SYSTEM = <<~PROMPT.strip
      Ты возвращаешь ТОЛЬКО один JSON-объект, без markdown и без текста до/после.
      Ключи: "intent", "slots" (объект или пустой), "assistant_message" (строка), "need_approval" (boolean).
      intent ∈ ["noop","add_note","update_lead","create_task","delete_lead","create_lead","add_knowledge"].
    PROMPT

    def initialize(client: nil)
      @client = client || Llm::OllamaClient.new
    end

    def call(transcript:, lead:, timezone: nil)
      transcript = normalize_transcript(transcript)
      ctx = build_lead_context(lead)
      tz = LeadIntentEnricher.resolve_timezone_string(timezone)

      parsed = parse_with_model(transcript, ctx)
      LeadIntentEnricher.apply!(parsed, transcript, timezone: tz)
      parsed
    rescue Llm::OllamaClient::Error => e
      {
        "intent" => "noop",
        "slots" => {},
        "assistant_message" => "Ошибка модели: #{e.message}",
        "need_approval" => false,
        "_error" => e.message
      }
    end

    private

    def parse_with_model(transcript, ctx)
      messages = primary_messages(transcript, ctx)
      response = @client.chat(messages: messages, format: "json", options: intent_model_options(is_retry: false))
      text = Llm::OllamaClient.message_content(response).to_s
      parsed = safe_parse_json(text)

      if parsed.nil? || !coherent_parsed?(parsed)
        messages_retry = retry_messages(transcript, ctx)
        response2 = @client.chat(messages: messages_retry, format: "json", options: intent_model_options(is_retry: true))
        text2 = Llm::OllamaClient.message_content(response2).to_s
        parsed = safe_parse_json(text2)
      end

      return fallback_parse_error if parsed.nil? || !coherent_parsed?(parsed)

      normalize_slots!(parsed)
      parsed
    end

    def primary_messages(transcript, ctx)
      [
        { "role" => "system", "content" => "Ты помощник CRM. #{SCHEMA_RULES}\n\n#{FEW_SHOT_EXAMPLES}" },
        { "role" => "user", "content" => "Контекст лида:\n#{ctx}\n\nРаспознанная речь:\n#{transcript}" }
      ]
    end

    def retry_messages(transcript, ctx)
      [
        { "role" => "system", "content" => RETRY_SYSTEM },
        { "role" => "user", "content" => "Контекст лида:\n#{ctx}\n\nРаспознанная речь:\n#{transcript}\n\nВерни только JSON с полями intent, slots, assistant_message, need_approval." }
      ]
    end

    def fallback_parse_error
      {
        "intent" => "noop",
        "slots" => {},
        "assistant_message" => "Не удалось разобрать JSON от модели.",
        "need_approval" => false
      }
    end

    def coherent_parsed?(h)
      return false unless h.is_a?(Hash)

      intent = h["intent"].to_s.strip
      return false if intent.blank?
      return false unless IntentRouter::ALLOWED_INTENTS.include?(intent)

      slots = h["slots"]
      return true if slots.nil?
      return false unless slots.is_a?(Hash)

      true
    end

    def normalize_slots!(h)
      h["slots"] = {} unless h["slots"].is_a?(Hash)
    end

    def safe_parse_json(text)
      parse_json_loose(text)
    rescue JSON::ParserError
      nil
    end

    # Убираем лишние пробелы и управляющие символы — модели и regex-энричеру проще.
    def normalize_transcript(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

    # Низкая temperature стабилизирует JSON; повтор второго запроса ещё ниже (ENV).
    def intent_model_options(is_retry: false)
      key = is_retry ? "OLLAMA_INTENT_RETRY_TEMPERATURE" : "OLLAMA_INTENT_TEMPERATURE"
      default = is_retry ? "0.05" : "0.2"
      t = ENV.fetch(key, default).to_f
      t = default.to_f if t.negative? || t > 2.0
      { "temperature" => t }
    end

    def build_lead_context(lead)
      return "(лид не выбран)" unless lead

      [
        "id=#{lead.id}",
        "company=#{lead.company_name}",
        "contact=#{lead.contact_name}",
        "email=#{lead.email}",
        "phone=#{lead.phone}",
        "stage=#{lead.stage}",
        "score=#{lead.score}",
        "next_call_at=#{lead.next_call_at&.iso8601}"
      ].join("\n")
    end

    def parse_json_loose(text)
      JSON.parse(text)
    rescue JSON::ParserError
      m = text.match(/\{[\s\S]*\}/m)
      raise JSON::ParserError, "no json in response" unless m

      JSON.parse(m[0])
    end
  end
end
