# frozen_string_literal: true

require "test_helper"

class KnowledgeDocumentTest < ActiveSupport::TestCase
  setup do
    @account = create_account!
  end

  test "requires pdf or body text on create" do
    doc = KnowledgeDocument.new(account: @account, title: "x")
    assert_not doc.valid?
    assert doc.errors[:base].present?
  end

  test "accepts body_text without file" do
    doc = KnowledgeDocument.new(account: @account, title: "Заметка", body_text: "Достаточно длинный текст для индекса.")
    assert doc.valid?
  end
end
