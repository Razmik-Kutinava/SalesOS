# frozen_string_literal: true

# Асинхронный запрос страницы через Playwright-воркер (если настроен PLAYWRIGHT_FETCH_URL).
class FetchUrlJob < ApplicationJob
  queue_as :default

  # @param lead_id [Integer]
  # @param url [String] полный URL
  # @param metadata [Hash] { actor_user_id: Integer }
  def perform(lead_id, url, metadata = {})
    lead = Lead.find_by(id: lead_id)
    return unless lead

    client = Fetch::PlaywrightClient.new
    raise Fetch::PlaywrightClient::ConfigurationError, "PLAYWRIGHT_FETCH_URL не задан" unless client.configured?

    result = client.fetch(url: url)

    Rails.logger.info("[FetchUrlJob] lead_id=#{lead_id} url=#{url.inspect} ok=#{result['ok']}")

    actor_user_id = metadata[:actor_user_id] || metadata["actor_user_id"]
    actor = actor_user_id.present? ? User.find_by(id: actor_user_id) : nil
    payload = result.is_a?(Hash) ? result : {}

    lead.lead_events.create!(
      actor: actor,
      event_type: "page_fetched",
      payload: {
        "url" => url,
        "ok" => payload["ok"],
        "finalUrl" => payload["finalUrl"],
        "title" => payload["title"],
        "statusCode" => payload["statusCode"],
        "htmlSize" => payload["htmlSize"],
        "text_excerpt" => payload["textContent"]&.to_s&.slice(0, 2000),
        "error" => payload["error"]
      }.compact
    )

    result
  rescue Fetch::PlaywrightClient::NotAllowedError => e
    actor_user_id = metadata[:actor_user_id] || metadata["actor_user_id"]
    actor = actor_user_id.present? ? User.find_by(id: actor_user_id) : nil
    lead.lead_events.create!(
      actor: actor,
      event_type: "page_fetched",
      payload: { "url" => url, "ok" => false, "error" => e.message }
    )
    raise
  rescue Fetch::PlaywrightClient::ConfigurationError
    # Не создаём события в историю, когда воркер/ENV не настроены:
    # это будет шумом, пока ты не включишь real worker.
    raise
  rescue Fetch::PlaywrightClient::HttpError => e
    actor_user_id = metadata[:actor_user_id] || metadata["actor_user_id"]
    actor = actor_user_id.present? ? User.find_by(id: actor_user_id) : nil
    lead.lead_events.create!(
      actor: actor,
      event_type: "page_fetched",
      payload: {
        "url" => url,
        "ok" => false,
        "error" => e.message,
        "statusCode" => e.status
      }
    )
    raise
  end
end
