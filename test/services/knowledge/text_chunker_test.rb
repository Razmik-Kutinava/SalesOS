# frozen_string_literal: true

require "test_helper"

class KnowledgeTextChunkerTest < ActiveSupport::TestCase
  test "splits long text" do
    t = ("word " * 500)
    chunks = Knowledge::TextChunker.call(t, chunk_size: 100, overlap: 20)
    assert_operator chunks.size, :>, 2
    assert chunks.all? { |c| c.length <= 100 }
  end
end
