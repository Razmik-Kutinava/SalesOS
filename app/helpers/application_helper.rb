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
      "lead_created_voice" => "Лид создан (голос)"
    }.fetch(event_type.to_s, event_type.to_s)
  end
end
