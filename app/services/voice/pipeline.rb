# frozen_string_literal: true

require "tempfile"

module Voice
  # Полный цикл: аудио → ASR → Ollama (JSON) → IntentRouter → VoiceSession.
  class Pipeline
    def initialize(user:, lead:, intent_parser: nil)
      @user = user
      @lead = lead
      @intent_parser = intent_parser || OllamaIntentParser.new
    end

    def call(uploaded_file)
      session = VoiceSession.create!(
        user: @user,
        lead: @lead,
        status: "processing"
      )

      path = write_temp(uploaded_file)
      transcript = begin
        Asr::WhisperRunner.transcribe(path)
      ensure
        File.unlink(path) if path && File.exist?(path)
      end
      session.update!(transcript: transcript)

      early = transcript_rejected_response(session, transcript)
      return early if early

      parsed = @intent_parser.call(transcript: transcript, lead: @lead, timezone: @user.timezone)
      session.update!(raw_llm_request: { "transcript" => transcript }, raw_llm_response: parsed)

      router = IntentRouter.new(user: @user, lead: @lead)
      result = router.call(parsed)

      session.update!(
        status: result.success ? "done" : "error",
        error_message: result.error_message
      )

      out = {
        voice_session_id: session.id,
        transcript: transcript,
        parsed: parsed,
        assistant_message: result.assistant_message,
        applied: result.applied,
        success: result.success,
        error: result.error_message
      }
      out[:created_lead_id] = result.created_lead_id if result.created_lead_id.present?
      out
    rescue Asr::WhisperRunner::ConfigurationError => e
      session&.update!(status: "error", error_message: e.message)
      raise
    rescue Asr::OpenaiWhisperClient::Error => e
      session&.update!(status: "error", error_message: e.message) if session&.persisted?
      {
        voice_session_id: session&.id,
        transcript: session&.transcript,
        success: false,
        error: e.message,
        assistant_message: e.message
      }
    rescue Asr::WhisperRunner::Error => e
      session&.update!(status: "error", error_message: e.message)
      {
        voice_session_id: session&.id,
        transcript: session&.transcript,
        success: false,
        error: e.message,
        assistant_message: "Ошибка распознавания речи."
      }
    rescue StandardError => e
      session&.update!(status: "error", error_message: e.message) if session&.persisted?
      Rails.logger.error("[Voice::Pipeline] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      {
        voice_session_id: session&.id,
        success: false,
        error: e.message,
        assistant_message: "Системная ошибка обработки голоса."
      }
    end

    private

    def transcript_rejected_response(session, transcript)
      t = transcript.to_s.strip
      if t.blank?
        session.update!(status: "error", error_message: "Пустой текст распознавания.")
        return {
          voice_session_id: session.id,
          transcript: transcript,
          success: false,
          error: "empty_transcript",
          assistant_message: "Пустой текст распознавания — скажи фразу громче или проверь микрофон."
        }
      end

      max = ENV.fetch("VOICE_TRANSCRIPT_MAX_CHARS", "8000").to_i
      if t.length > max
        msg = "Текст распознавания слишком длинный (макс. #{max} символов)."
        session.update!(status: "error", error_message: msg)
        return {
          voice_session_id: session.id,
          transcript: transcript,
          success: false,
          error: "transcript_too_long",
          assistant_message: msg
        }
      end

      nil
    end

    def write_temp(uploaded_file)
      ext = File.extname(uploaded_file.original_filename.presence || ".webm")
      tmp = Tempfile.new([ "voice", ext ])
      tmp.binmode
      tmp.write(uploaded_file.read)
      tmp.rewind
      tmp.close
      tmp.path
    end
  end
end
