# frozen_string_literal: true

module Knowledge
  # Вопрос → Retriever → Ollama chat с контекстом; без релевантных чанков — ответ без «галлюцинаций».
  class RagAnswer
    Result = Data.define(:answer, :sources, :grounded, :error)

    def self.call(account:, question:, k: nil, client: nil, hits: nil)
      k ||= ENV.fetch("RAG_TOP_K", "5").to_i
      q = question.to_s.strip
      return Result.new(answer: nil, sources: [], grounded: false, error: "Пустой вопрос") if q.blank?

      found = hits.nil? ? Retriever.search(account: account, query: q, k: k) : hits
      min_score = ENV.fetch("RAG_MIN_SCORE", "0.12").to_f
      found = found.select { |h| h.score >= min_score }

      if found.empty?
        return Result.new(
          answer: "В базе знаний нет релевантных фрагментов по этому запросу. Загрузите PDF, добавьте текстовую заметку или уточните формулировку.",
          sources: [],
          grounded: false,
          error: nil
        )
      end

      context_block = found.map.with_index do |h, i|
        title = h.chunk.knowledge_document.display_title
        "[#{i + 1}] (#{title})\n#{h.chunk.content}"
      end.join("\n\n---\n\n")

      messages = [
        { "role" => "system", "content" => system_prompt },
        { "role" => "user", "content" => "Контекст из базы знаний:\n\n#{context_block}\n\nВопрос пользователя:\n#{q}" }
      ]

      ollama = client || Llm::OllamaClient.new
      resp = ollama.chat(messages: messages, options: chat_options)
      text = Llm::OllamaClient.message_content(resp).to_s.strip

      sources = found.map do |h|
        {
          document_title: h.chunk.knowledge_document.display_title,
          score: h.score.round(4),
          excerpt: h.chunk.content.truncate(200)
        }
      end

      Result.new(answer: text, sources: sources, grounded: true, error: nil)
    rescue Llm::OllamaClient::Error => e
      Result.new(answer: nil, sources: [], grounded: false, error: e.message)
    end

    def self.system_prompt
      <<~TXT.strip
        Ты помощник по корпоративной базе знаний. Отвечай только на основе переданного контекста.
        Если в контексте нет данных для ответа — напиши об этом прямо. Пиши по-русски, кратко и по делу.
        Можешь ссылаться на номера фрагментов [1], [2] и т.д.
      TXT
    end

    def self.chat_options
      t = ENV.fetch("OLLAMA_RAG_TEMPERATURE", "0.3").to_f
      t = 0.3 if t.negative? || t > 2.0
      { "temperature" => t }
    end
  end
end
