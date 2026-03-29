# frozen_string_literal: true

# Переменные: OLLAMA_HOST, OLLAMA_MODEL, OLLAMA_OPEN_TIMEOUT, OLLAMA_READ_TIMEOUT
# Подробно: docs/integrations/OLLAMA-RAILS-INTEGRATION.md

Rails.application.config.ollama = ActiveSupport::OrderedOptions.new

Rails.application.config.after_initialize do
  cfg = Llm::OllamaClient::Configuration.from_env
  Rails.application.config.ollama.base_url = cfg.base_url
  Rails.application.config.ollama.default_model = cfg.default_model
rescue Llm::OllamaClient::ConfigurationError => e
  Rails.logger.warn("[Ollama] #{e.message}") if defined?(Rails.logger)
end
