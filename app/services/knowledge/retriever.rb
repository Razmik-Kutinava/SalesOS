# frozen_string_literal: true

module Knowledge
  # Семантический top-k по косинусной близости (эмбеддинги в JSON, без pgvector).
  class Retriever
    Result = Data.define(:chunk, :score)

    def self.search(account:, query:, k: 5)
      q = query.to_s.strip
      return [] if q.blank?

      client = Llm::OllamaClient.new
      qvec = Llm::OllamaClient.embedding_vector(client.embed(prompt: q))

      chunks = KnowledgeChunk
        .joins(:knowledge_document)
        .where(account_id: account.id, knowledge_documents: { status: "ready" })
        .includes(:knowledge_document)
      scored = chunks.map { |c| [ c, cosine_similarity(c.embedding_vector, qvec ) ] }
      scored.sort_by { |_, s| -s }.first(k.to_i.clamp(1, 20)).map { |c, s| Result.new(chunk: c, score: s) }
    rescue Llm::OllamaClient::Error
      []
    end

    def self.cosine_similarity(a, b)
      return 0.0 if a.blank? || b.blank? || a.length != b.length

      dot = a.each_index.sum { |i| a[i] * b[i] }
      na = Math.sqrt(a.sum { |x| x * x })
      nb = Math.sqrt(b.sum { |x| x * x })
      return 0.0 if na.zero? || nb.zero?

      dot / (na * nb)
    end
  end
end
