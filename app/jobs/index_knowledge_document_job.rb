# frozen_string_literal: true

class IndexKnowledgeDocumentJob < ApplicationJob
  queue_as :default

  # Индексация PDF → чанки → эмбеддинги Ollama → SQLite (embedding_json).
  def perform(knowledge_document_id)
    doc = KnowledgeDocument.find_by(id: knowledge_document_id)
    return unless doc

    doc.update!(status: "processing", error_message: nil)
    client = Llm::OllamaClient.new

    text = extract_text(doc)
    chunks = Knowledge::TextChunker.call(text)
    if chunks.empty?
      doc.update!(status: "failed", error_message: "Нет текста для индексации после разбиения.")
      return
    end

    doc.knowledge_chunks.delete_all

    chunks.each_with_index do |content, idx|
      response = client.embed(prompt: content)
      vec = Llm::OllamaClient.embedding_vector(response)
      doc.knowledge_chunks.create!(
        account_id: doc.account_id,
        chunk_index: idx,
        content: content,
        embedding_json: vec.to_json,
        metadata: { "chars" => content.length }
      )
    end

    doc.update!(status: "ready", error_message: nil)
  rescue Knowledge::PdfExtractor::Error => e
    doc.update!(status: "failed", error_message: e.message)
  rescue Llm::OllamaClient::Error => e
    doc.update!(status: "failed", error_message: "Ollama: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[IndexKnowledgeDocumentJob] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
    doc.update!(status: "failed", error_message: e.message.to_s.truncate(500))
  end

  private

  def extract_text(doc)
    if doc.body_text.present?
      return doc.body_text.to_s
    end

    unless doc.file.attached?
      raise Knowledge::PdfExtractor::Error, "Нет текста и нет файла"
    end

    doc.file.blob.open do |io|
      Knowledge::PdfExtractor.call(io)
    end
  end
end
