# frozen_string_literal: true

module Knowledge
  class TextChunker
    def self.call(text, chunk_size: nil, overlap: nil)
      size = chunk_size || ENV.fetch("RAG_CHUNK_SIZE", "900").to_i
      ov = overlap || ENV.fetch("RAG_CHUNK_OVERLAP", "120").to_i
      step = [ size - ov, 1 ].max

      t = text.to_s.strip
      return [] if t.blank?

      chunks = []
      i = 0
      while i < t.length
        piece = t[i, size]&.strip
        chunks << piece if piece.present?
        i += step
      end
      chunks
    end
  end
end
