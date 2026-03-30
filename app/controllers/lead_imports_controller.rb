# frozen_string_literal: true

class LeadImportsController < ApplicationController
  before_action :require_authentication
  before_action :set_lead_import, only: %i[show edit update]

  def create
    file = lead_import_params[:file]
    if file.blank?
      redirect_to root_path(tab: "import"), alert: "Выберите файл CSV или Excel."
      return
    end

    @lead_import = current_user.account.lead_imports.build(user: current_user)
    @lead_import.file.attach(file)

    unless @lead_import.save
      redirect_to root_path(tab: "import"), alert: @lead_import.errors.full_messages.join(" ")
      return
    end

    apply_headers_and_mapping!(@lead_import)
    ProcessLeadImportJob.perform_later(@lead_import.id)
    redirect_to lead_import_path(@lead_import), notice: "Файл принят, импорт поставлен в очередь."
  rescue Imports::SpreadsheetReader::Error => e
    @lead_import&.destroy
    redirect_to root_path(tab: "import"), alert: e.message
  rescue StandardError => e
    Rails.logger.error("[LeadImportsController#create] #{e.class}: #{e.message}")
    @lead_import&.destroy
    redirect_to root_path(tab: "import"), alert: "Не удалось прочитать файл: #{e.message}"
  end

  def show; end

  def edit
    @headers = @lead_import.preview_headers
  end

  def update
    raw = column_mapping_params_hash
    mapping = normalize_column_mapping_param(raw)
    @lead_import.update!(
      column_mapping: mapping,
      status: "queued",
      result_summary: {},
      error_message: nil
    )
    ProcessLeadImportJob.perform_later(@lead_import.id)
    redirect_to lead_import_path(@lead_import), notice: "Маппинг сохранён, импорт запущен снова."
  end

  private

  def set_lead_import
    @lead_import = current_user.account.lead_imports.find(params[:id])
  end

  def lead_import_params
    p = params[:lead_import]
    return {} if p.blank?

    p.permit(:file, :use_llm_mapping)
  end

  def column_mapping_params_hash
    h = params[:column_mapping]
    return {} if h.blank?

    h = h.permit(*Imports::ColumnMapper::FIELD_KEYS) if h.respond_to?(:permit)
    h.to_h
  end

  def apply_headers_and_mapping!(lead_import)
    use_llm = ActiveModel::Type::Boolean.new.cast(lead_import_params[:use_llm_mapping])
    client = use_llm ? Llm::OllamaClient.new : nil

    lead_import.file.blob.open do |tmp|
      ext = Imports::SpreadsheetReader.extension_for(lead_import.file.filename.to_s)
      headers = Imports::SpreadsheetReader.headers_from_path(tmp.path, ext)
      mapping, llm_used = Imports::ColumnMapper.build(headers: headers, use_llm: use_llm, client: client)
      lead_import.update!(
        preview_headers: headers,
        column_mapping: mapping,
        llm_mapping_used: llm_used,
        status: "queued"
      )
    end
  end

  def normalize_column_mapping_param(raw)
    return {} if raw.blank?

    h = raw.stringify_keys
    out = {}
    Imports::ColumnMapper::FIELD_KEYS.each do |k|
      v = h[k]
      out[k] = v.to_s.strip if v.present?
    end
    out.compact_blank
  end

end
