module ApplicationHelper
  # :stub | :openai | :local | :none
  def voice_asr_mode
    return :stub if Asr::WhisperRunner.stub_mode?(rails_env: Rails.env, env: ENV)
    return :openai if Asr::WhisperRunner.openai_asr?
    return :local if Asr::WhisperRunner.whisper_bin.present? && Asr::WhisperRunner.whisper_model.present?

    :none
  end

  def lead_event_label(event_type)
    {
      "voice_note" => "Голос: заметка",
      "lead_updated" => "Поля лида",
      "task_created" => "Задача создана",
      "delete_requested" => "Заявка на удаление",
      "lead_discarded" => "Лид удалён (архив)",
      "lead_created_voice" => "Лид создан (голос)",
      "lead_imported" => "Импорт строки",
      "page_fetched" => "Playwright: страница",
      "search_performed" => "Search: запрос",
      "search_approved" => "Search: одобрено"
    }.fetch(event_type.to_s, event_type.to_s)
  end

  def lead_import_field_labels
    {
      "company_name" => "Компания",
      "contact_name" => "Контакт",
      "email" => "Email",
      "phone" => "Телефон",
      "stage" => "Стадия"
    }
  end

  def lead_import_status_label(status)
    {
      "pending" => "Ожидает",
      "queued" => "В очереди",
      "processing" => "Обработка",
      "completed" => "Готово",
      "failed" => "Ошибка"
    }.fetch(status.to_s, status.to_s)
  end
end
