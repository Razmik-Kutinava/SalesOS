# frozen_string_literal: true

module Voice
  # Агрегация по сохранённым VoiceSession: статусы, распределение intent из raw_llm_response, частые ошибки.
  class SessionInsights
    def self.report(since: 7.days.ago)
      scope = VoiceSession.where("created_at >= ?", since)

      {
        since: since,
        total: scope.count,
        by_status: scope.group(:status).count,
        intent_histogram: intent_histogram(scope.where(status: "done")),
        error_histogram: error_histogram(scope.where(status: "error")),
        success_rate: success_rate(scope)
      }
    end

    def self.intent_histogram(done_scope)
      counts = Hash.new(0)
      done_scope.find_each do |s|
        intent = s.raw_llm_response&.dig("intent") || s.raw_llm_response&.dig(:intent)
        key = intent.presence || "unknown"
        counts[key.to_s] += 1
      end
      counts.sort_by { |_, n| -n }.to_h
    end

    def self.error_histogram(error_scope)
      h = Hash.new(0)
      error_scope.find_each do |s|
        key = s.error_message.to_s.strip.presence || "(пусто)"
        h[key] += 1
      end
      h.sort_by { |_, n| -n }.to_h
    end

    def self.success_rate(scope)
      total = scope.count
      return 0.0 if total.zero?

      (scope.where(status: "done").count.to_f / total * 100).round(1)
    end

    def self.format_report(since: 7.days.ago)
      r = report(since: since)
      lines = []
      lines << "VoiceSession с #{r[:since].iso8601}"
      lines << "Всего: #{r[:total]}, успешных (done): #{r[:success_rate]}% от всех записей"
      lines << "По статусам: #{r[:by_status].inspect}"
      lines << "Интенты (done): #{r[:intent_histogram].inspect}"
      lines << "Ошибки (error): #{r[:error_histogram].inspect}"
      lines.join("\n")
    end
  end
end
