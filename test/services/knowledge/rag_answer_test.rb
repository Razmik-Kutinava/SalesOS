# frozen_string_literal: true

require "test_helper"

class KnowledgeRagAnswerTest < ActiveSupport::TestCase
  setup do
    @account = create_account!
  end

  test "empty question returns error result" do
    r = Knowledge::RagAnswer.call(account: @account, question: "   ", hits: [])
    assert_nil r.answer
    assert_not r.grounded
    assert_equal "Пустой вопрос", r.error
  end

  test "no hits after min_score yields ungrounded message" do
    doc = KnowledgeDocument.create!(
      account: @account,
      title: "T",
      body_text: "x" * 20,
      status: "ready"
    )
    kc = doc.knowledge_chunks.create!(
      account_id: @account.id,
      chunk_index: 0,
      content: "мало",
      embedding_json: [ 1.0 ].to_json
    )
    hit = Knowledge::Retriever::Result.new(chunk: kc, score: 0.01)
    r = Knowledge::RagAnswer.call(account: @account, question: "цена", hits: [ hit ])
    assert_not r.grounded
    assert_match(/нет релевантных/i, r.answer.to_s)
  end

  test "with hits and stub client returns answer" do
    doc = KnowledgeDocument.create!(
      account: @account,
      title: "T",
      body_text: "x" * 20,
      status: "ready"
    )
    kc = doc.knowledge_chunks.create!(
      account_id: @account.id,
      chunk_index: 0,
      content: "Скидка 10%",
      embedding_json: [ 1.0, 0.0, 0.0 ].to_json
    )
    hit = Knowledge::Retriever::Result.new(chunk: kc, score: 0.95 )

    client = Object.new
    def client.chat(messages:, model: nil, format: nil, options: nil)
      { "message" => { "content" => "Да, скидка 10%." } }
    end

    r = Knowledge::RagAnswer.call(account: @account, question: "Какая скидка?", hits: [ hit ], client: client)
    assert r.grounded
    assert_equal "Да, скидка 10%.", r.answer
    assert_equal 1, r.sources.size
  end
end
