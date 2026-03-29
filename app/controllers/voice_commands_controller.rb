# frozen_string_literal: true

class VoiceCommandsController < ApplicationController
  before_action :require_authentication
  before_action :set_lead, only: [ :create ]

  # POST /leads/:id/voice — multipart, поле audio (контекст выбранного лида)
  def create
    audio = params[:audio]
    if audio.blank?
      return render json: { success: false, error: "Нет файла audio" }, status: :unprocessable_entity
    end

    if audio.size > 15.megabytes
      return render json: { success: false, error: "Файл больше 15 МБ" }, status: :payload_too_large
    end

    pipeline = Voice::Pipeline.new(user: current_user, lead: @lead)
    result = pipeline.call(audio)
    status = result[:success] ? :ok : :unprocessable_entity
    render json: result, status: status
  rescue Asr::WhisperRunner::ConfigurationError => e
    render json: {
      success: false,
      error: e.message,
      hint: "В development заглушка ASR включается сама, если не заданы Whisper/OpenAI. Иначе: VOICE_ASR_STUB=1, WHISPER_BIN+WHISPER_MODEL, или ASR_BACKEND=openai + OPENAI_API_KEY (см. docs/integrations/OPENAI-WHISPER-API.md)."
    }, status: :unprocessable_entity
  end

  # POST /console/voice — когда в аккаунте нет активных лидов: создать лид голосом (create_lead)
  def create_console
    audio = params[:audio]
    if audio.blank?
      return render json: { success: false, error: "Нет файла audio" }, status: :unprocessable_entity
    end

    if audio.size > 15.megabytes
      return render json: { success: false, error: "Файл больше 15 МБ" }, status: :payload_too_large
    end

    pipeline = Voice::Pipeline.new(user: current_user, lead: nil)
    result = pipeline.call(audio)
    status = result[:success] ? :ok : :unprocessable_entity
    render json: result, status: status
  rescue Asr::WhisperRunner::ConfigurationError => e
    render json: {
      success: false,
      error: e.message,
      hint: "Настрой ASR в .env (см. docs/integrations/LOCAL-WHISPER-SETUP.md)."
    }, status: :unprocessable_entity
  end

  private

  def set_lead
    account = current_user.account
    id = params[:id]
    @lead = account.leads.kept.find_by(id: id)
    return if @lead

    if account.leads.where(id: id).where.not(discarded_at: nil).exists?
      render json: {
        success: false,
        error: "Этот лид уже удалён (архив). Обновите страницу.",
        lead_gone: true
      }, status: :gone
      return
    end

    render json: { success: false, error: "Лид не найден" }, status: :not_found
  end
end
