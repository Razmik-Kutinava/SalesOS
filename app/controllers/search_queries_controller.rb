# frozen_string_literal: true

class SearchQueriesController < ApplicationController
  before_action :require_authentication
  before_action :set_lead

  # POST /leads/:id/search
  def create
    return if @lead.nil?

    query = permitted_search_params[:query].to_s.strip
    if query.blank?
      redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: "Укажите запрос"
      return
    end

    trusted_domains = permitted_search_params[:trusted_domains].to_s

    Search::SearchAndParse.call(
      lead: @lead,
      query: query,
      actor_user_id: current_user.id,
      trusted_domains: trusted_domains
    )
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), notice: "Поиск и проверка завершены."
  rescue Fetch::PlaywrightClient::Error => e
    # NotAllowed / worker config errors: we still want search to be present.
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: e.message
  rescue Search::BaseHttpClient::Error => e
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: "Поиск API: #{e.message}"
  rescue StandardError => e
    Rails.logger.error("[SearchQueriesController#create] #{e.class}: #{e.message}")
    redirect_to root_path(lead_id: @lead.id, tab: "parse"), alert: "Не удалось выполнить поиск"
  end

  private

  def set_lead
    @lead = current_user.account.leads.kept.find_by(id: params[:id])
    redirect_to root_path, alert: "Лид не найден" if @lead.nil?
  end

  def permitted_search_params
    params.permit(:query, :trusted_domains)
  end
end

