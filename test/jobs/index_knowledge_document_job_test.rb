# frozen_string_literal: true

require "test_helper"

class IndexKnowledgeDocumentJobTest < ActiveJob::TestCase
  test "perform is no-op when document id unknown" do
    assert_nothing_raised { IndexKnowledgeDocumentJob.perform_now(0) }
  end
end
