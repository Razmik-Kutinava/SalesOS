# frozen_string_literal: true

module Voice
  # Если модель вернула add_note, но в речи явно просят изменить поля лида — поднимаем до update_lead.
  module LeadIntentEnricher
    module_function

    # timezone — IANA-строка из users.timezone (например Europe/Moscow); даты «завтра»/«в пятницу» считаются в этой зоне.
    def apply!(parsed, transcript, timezone: nil)
      return parsed unless parsed.is_a?(Hash)

      tz = resolve_timezone_string(timezone)
      promote_to_delete_lead!(parsed, transcript)
      promote_to_create_lead!(parsed, transcript)
      promote_add_note_to_update!(parsed, transcript, timezone: tz)
      parsed
    end

    def resolve_timezone_string(tz)
      s = tz.to_s.strip
      s = "UTC" if s.blank?
      Time.find_zone(s) ? s : "UTC"
    end

    def promote_to_create_lead!(parsed, transcript)
      return if %w[create_lead delete_lead add_knowledge].include?(parsed["intent"].to_s)

      text = "#{transcript} #{parsed.dig('slots', 'note')}".to_s
      return unless wants_create_lead?(text)

      parsed["intent"] = "create_lead"
      parsed["slots"] = (parsed["slots"].is_a?(Hash) ? parsed["slots"].stringify_keys : {}).merge(
        "company_name" => parsed.dig("slots", "company_name").presence || extract_company_guess(text)
      ).compact_blank
      parsed["assistant_message"] = parsed["assistant_message"].presence || "Создаю новый лид."
    end

    def wants_create_lead?(text)
      t = text.downcase
      t.match?(/(?:создай|создать|добавь)\s+лид|новый\s+лид|добавь\s+компани|новый\s+контакт/i)
    end

    def extract_company_guess(text)
      m = text.match(/компани[яи]\s+([^,.;]{2,80})/i)
      return m[1].strip if m
      m = text.match(/лид[а]?\s*,?\s*([^,.;]{2,80})/i)
      return m[1].strip if m

      nil
    end

    def promote_to_delete_lead!(parsed, transcript)
      return if parsed["intent"].to_s == "delete_lead"

      text = "#{transcript} #{parsed.dig('slots', 'note')}".to_s
      return unless explicit_delete_lead_command?(text)

      parsed["intent"] = "delete_lead"
      parsed["slots"] = {}
      parsed["assistant_message"] = parsed["assistant_message"].presence || "Лид удалён из активных."
    end

    def explicit_delete_lead_command?(text)
      t = text.downcase
      return false if t.match?(/удали(?:ть)?\s+(?:замет|поле|email|телефон|номер)/i)

      t.match?(/(?:удали|убери|закрой)\s+(?:этот\s+)?(?:лид|контакт)(?:\s|$|[,.])/i) ||
        t.match?(/(?:удали|убери)\s+(?:этот\s+)?(?:лид|контакт)\s+из\s+активн/i)
    end

    def promote_add_note_to_update!(parsed, transcript, timezone: "UTC")
      return unless parsed["intent"].to_s == "add_note"

      slots = (parsed["slots"] || {}).stringify_keys
      note = slots["note"].to_s
      raw = "#{transcript} #{note}"
      normalized = normalize_spoken_email(raw)
      return unless wants_structured_lead_change?(normalized)

      extracted = extract_lead_slots(normalized, timezone: timezone)
      return if extracted.empty?

      parsed["intent"] = "update_lead"
      parsed["slots"] = extracted.merge(slots.except("note"))
      parsed["assistant_message"] = parsed["assistant_message"].presence || "Поля лида обновлены."
    end

    # \w в Ruby не покрывает кириллицу — используем \p{L} для «следующий звонок» и т.п.
    CALL_RELATED_RE = /(?:перезвон|позвонить|следующ[\p{L}]+\s+(?:звонок|связ)|запланир[\p{L}]*\s+звонок|напомнить\s+о\s+звонке)/i.freeze

    def wants_structured_lead_change?(text)
      t = text.to_s
      return true if t.match?(/[\w.+-]+@[\w.-]+\.[a-z]{2,}/i)
      return true if t.match?(/(?:установ|постав|запиш|измен|обнов|пропиш|укажи|внеси|поменяй|добавь\s+в\s+лид|в\s+лид[еа])/i)
      return true if t.match?(/(?:email|почт|телефон|контакт|компани|этап|стадия|скоринг|оценк)/i)
      # Следующий звонок / перезвон по дате — то же обновление карточки лида
      if t.match?(/(?:завтра|послезавтра|сегодня)/i) &&
          t.match?(CALL_RELATED_RE)
        return true
      end
      if weekday_mentioned?(t) && t.match?(CALL_RELATED_RE)
        return true
      end
      false
    end

    def weekday_mentioned?(text)
      text.match?(/(?:понедельник|вторник|среду|среда|четверг|пятницу|пятница|субботу|суббота|воскресенье|воскресенья)/i)
    end

    # «имя собака domain.ru» → имя@domain.ru
    def normalize_spoken_email(text)
      t = text.to_s.dup
      t.gsub!(/(\S+)\s+собака\s+(\S+)/i, '\1@\2')
      t
    end

    def extract_lead_slots(text, timezone: "UTC")
      h = {}
      if (m = text.match(/([\w.+-]+@[\w.-]+\.[a-z]{2,})/i))
        h["email"] = m[1].downcase
      end
      if text.match?(/(?:телефон|тел\.|mobile|phone|номер|плюс|\+7|\+)/i)
        if (m = text.match(/(\+?\d[\d\s\-()]{10,})/))
          digits = m[1].to_s.gsub(/\D/, "")
          p = format_phone_slot(m[1].to_s, digits)
          h["phone"] = p if p
        end
      end
      stage = extract_stage(text)
      h["stage"] = stage if stage
      score = extract_score(text)
      h["score"] = score if score
      nc = extract_next_call_at(text, timezone: timezone)
      h["next_call_at"] = nc if nc.present?
      h
    end

    # Речь «перезвонить завтра в 15», «в пятницу в 11», «следующий звонок послезавтра» → ISO8601 для update_lead.
    def extract_next_call_at(text, timezone: "UTC")
      raw = text.to_s
      return nil unless raw.match?(
        /(?:перезвон|позвонить|следующ[\p{L}]+\s+(?:звонок|связ)|запланир[\p{L}]*\s+звонок|next\s*[_\s]?call|напомнить\s+о\s+звонке)/i
      )

      zone = Time.find_zone(timezone) || Time.find_zone!("UTC")
      now = zone.now
      d = nil
      tl = raw.downcase

      if (wday = detect_weekday_wday(raw))
        d = next_occurrence_date_for_wday(now.to_date, wday)
      elsif tl.match?(/(?:\bзавтра\b|\bпослезавтра\b|\bсегодня\b)/)
        d = now.to_date
        d += 2 if tl.include?("послезавтра")
        d += 1 if tl.match?(/\bзавтра\b/)
      end

      return nil unless d

      hour = 10
      min = 0
      if (m = raw.match(/(?:в|на)\s+(\d{1,2})(?::(\d{2}))?/))
        hour = m[1].to_i.clamp(0, 23)
        min = m[2] ? m[2].to_i.clamp(0, 59) : 0
      end

      zone.local(d.year, d.month, d.day, hour, min).iso8601
    end

    # Date#wday: 0=воскресенье … 6=суббота
    def detect_weekday_wday(text)
      WEEKDAY_RU_PATTERNS.each do |re, wday|
        return wday if text.match?(re)
      end
      nil
    end

    WEEKDAY_RU_PATTERNS = [
      [ /понедельник/i, 1 ],
      [ /вторник/i, 2 ],
      [ /(?:среду|среда)/i, 3 ],
      [ /четверг/i, 4 ],
      [ /(?:пятницу|пятница)/i, 5 ],
      [ /(?:субботу|суббота)/i, 6 ],
      [ /(?:воскресенье|воскресенья)/i, 0 ]
    ].freeze

    def next_occurrence_date_for_wday(from_date, target_wday)
      0.upto(6) do |add|
        cand = from_date + add
        return cand if cand.wday == target_wday
      end
      from_date + 7
    end

    def format_phone_slot(original, digits)
      return "+#{digits}" if original.include?("+") && digits.length >= 10
      return digits if digits.length >= 10

      nil
    end

    def extract_stage(text)
      Lead::STAGES.each do |st|
        return st if text.match?(/\b#{Regexp.escape(st)}\b/i)
      end
      # русские подсказки
      map = {
        "новый" => "new", "новая" => "new",
        "квалифицирован" => "qualified",
        "предложение" => "proposal", "коммерческое" => "proposal",
        "переговор" => "negotiation", "переговоры" => "negotiation",
        "выигран" => "won", "won" => "won",
        "проигран" => "lost", "lost" => "lost"
      }
      t = text.downcase
      map.each do |word, st|
        return st if t.include?(word)
      end
      nil
    end

    def extract_score(text)
      if (m = text.match(/(?:скоринг|оценк|score)[:\s]+(\d{1,3})/i))
        s = m[1].to_i
        return s if s <= 100
      end
      if (m = text.match(/\b(\d{1,3})\s*(?:из\s*100|балл)/i))
        s = m[1].to_i
        return s if s <= 100
      end
      nil
    end
  end
end
