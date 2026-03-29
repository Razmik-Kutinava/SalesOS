# frozen_string_literal: true

module Voice
  # Эталонные фразы для rake `voice:golden_check` и ручной регрессии интентов.
  # expect_intent — ожидаемое поле intent после Ollama + LeadIntentEnricher (без IntentRouter).
  module GoldenPhrases
    Entry = Data.define(:id, :text, :expect_intent)

    LIST = [
      Entry.new(id: :noop_noise, text: "спасибо за просмотр подпишись на канал", expect_intent: "noop"),
      Entry.new(id: :delete_explicit, text: "Удали этот лид", expect_intent: "delete_lead"),
      Entry.new(id: :create_company, text: "Создай лид, компания Вега, контакт Олег", expect_intent: "create_lead"),
      Entry.new(id: :update_email, text: "Поставь email client@example.com", expect_intent: "update_lead"),
      Entry.new(id: :add_note_only, text: "Коротко: клиент отложил решение на неделю без цифр и почты", expect_intent: "add_note"),
      Entry.new(id: :task_title, text: "Задача: отправить коммерческое предложение до пятницы", expect_intent: "create_task")
    ].freeze

    # Возвращает массив хэшей { entry:, parsed:, ok:, mismatch: }
    def self.run_against_parser(lead:, timezone: "UTC", parser: nil)
      p = parser || OllamaIntentParser.new
      LIST.map do |entry|
        parsed = p.call(transcript: entry.text, lead: lead, timezone: timezone)
        got = parsed["intent"].to_s
        ok = (got == entry.expect_intent)
        mismatch = ok ? nil : "ожидали #{entry.expect_intent}, получили #{got}"
        { entry: entry, parsed: parsed, ok: ok, mismatch: mismatch }
      end
    end
  end
end
