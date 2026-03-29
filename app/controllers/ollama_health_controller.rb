# frozen_string_literal: true

# JSON health для Ollama (curl / мониторинг). Не наследуем ApplicationController — там allow_browser для HTML.
class OllamaHealthController < ActionController::API
  def show
    client = Llm::OllamaClient.new
    tags = client.tags
    render json: {
      ok: true,
      base_url: client.config.base_url,
      default_model: client.config.default_model,
      models: tags.fetch("models", []).filter_map { |m| m["name"] }
    }
  rescue Llm::OllamaClient::Error => e
    render json: {
      ok: false,
      error: e.class.name,
      message: e.message
    }, status: :service_unavailable
  end
end
