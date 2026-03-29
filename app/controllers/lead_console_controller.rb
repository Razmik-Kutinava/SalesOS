# frozen_string_literal: true

# Одна страница: таблица лидов (как в БД) + голос для выбранного или создание лида без таблицы.
class LeadConsoleController < ApplicationController
  before_action :require_authentication

  def show
    @leads = current_user.account.leads.kept.order(updated_at: :desc)
    @selected_lead = resolve_selected_lead
    redirect_if_stale_lead_param!
    return if performed?

    @console_tab = console_tab_param || "leads"
    @lead_events = load_lead_events
    @voice_post_path = voice_post_path_for_ui
    @knowledge_documents = current_user.account.knowledge_documents.order(created_at: :desc).limit(30)
  end

  private

  def console_tab_param
    params[:tab].presence_in(%w[leads rag])
  end

  def resolve_selected_lead
    if params[:lead_id].present?
      lead = current_user.account.leads.kept.find_by(id: params[:lead_id])
      return lead if lead
    end
    @leads.first
  end

  def redirect_if_stale_lead_param!
    return unless params[:lead_id].present?

    if @leads.empty?
      redirect_to root_path
      return
    end

    return unless @selected_lead

    return if params[:lead_id].to_i == @selected_lead.id

    redirect_to root_path(lead_id: @selected_lead.id, tab: console_tab_param)
  end

  def voice_post_path_for_ui
    target = @selected_lead || @leads.first
    return voice_lead_path(target) if target

    voice_console_path
  end

  def load_lead_events
    return LeadEvent.none unless @selected_lead

    @selected_lead.lead_events.includes(:actor).order(created_at: :desc).limit(30)
  end
end
