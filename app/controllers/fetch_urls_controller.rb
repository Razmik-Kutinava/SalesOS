# frozen_string_literal: true

class FetchUrlsController < ApplicationController
  before_action :require_authentication
  before_action :set_lead

  # POST /leads/:id/fetch_url
  # UI: отправляем URL → Rails вызывает Playwright worker → сохраняем результат в LeadEvent.
  def create
    return if @lead.nil?

    url = permitted_fetch_url
    if url.blank?
      redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: "Укажите URL"
      return
    end

    FetchUrlJob.perform_now(@lead.id, url, actor_user_id: current_user.id)
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), notice: "Страница получена."
  rescue Fetch::PlaywrightClient::NotAllowedError => e
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: e.message
  rescue Fetch::PlaywrightClient::ConfigurationError => e
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: e.message
  rescue Fetch::PlaywrightClient::HttpError => e
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: "Ошибка FetchUrl: #{e.status}"
  rescue StandardError => e
    Rails.logger.error("[FetchUrlsController#create] #{e.class}: #{e.message}")
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: "Не удалось получить страницу"
  end

  private

  def set_lead
    @lead = current_user.account.leads.kept.find_by(id: params[:id])
    if @lead.nil?
      redirect_to root_path, alert: "Лид не найден"
      return
    end
  end

  def permitted_fetch_url
    permitted = params.permit(:url)
    permitted[:url].to_s.strip
  end
end

