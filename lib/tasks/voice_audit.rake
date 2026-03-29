# frozen_string_literal: true

namespace :voice do
  desc "Сводка по VoiceSession за период (статусы, интенты, ошибки). DAYS=7 по умолчанию"
  task session_insights: :environment do
    days = ENV.fetch("DAYS", "7").to_i
    days = 7 if days <= 0
    puts Voice::SessionInsights.format_report(since: days.days.ago)
  end

  desc "Прогон эталонных фраз через OllamaIntentParser (нужен доступный Ollama). LEAD_ID= опционально"
  task golden_check: :environment do
    client = Llm::OllamaClient.new
    unless client.reachable?
      puts "Ollama недоступна (#{Llm::OllamaClient::Configuration.from_env.base_url}). Пропуск."
      exit 1
    end

    lead = nil
    if ENV["LEAD_ID"].present?
      lead = Lead.find_by(id: ENV["LEAD_ID"].to_i)
      puts "Контекст лида: id=#{lead&.id || 'не найден'}"
    end

    tz = ENV["TIMEZONE"].presence || User.first&.timezone || "UTC"
    results = Voice::GoldenPhrases.run_against_parser(lead: lead, timezone: tz)

    ok_n = results.count { |x| x[:ok] }
    puts "Golden: #{ok_n}/#{results.size} совпали с ожидаемым intent"
    results.each do |r|
      e = r[:entry]
      status = r[:ok] ? "OK" : "FAIL"
      puts "  [#{status}] #{e.id}: #{r[:mismatch] || "intent=#{r[:parsed]['intent']}"}"
      puts "      фраза: #{e.text[0, 120]}#{'…' if e.text.length > 120}"
    end

    exit(results.all? { |x| x[:ok] } ? 0 : 2)
  end
end
