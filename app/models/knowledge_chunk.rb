# frozen_string_literal: true

class KnowledgeChunk < ApplicationRecord
  belongs_to :knowledge_document
  belongs_to :account

  validates :chunk_index, presence: true
  validates :content, presence: true
  validates :embedding_json, presence: true

  def embedding_vector
    JSON.parse(embedding_json)
  end
end
