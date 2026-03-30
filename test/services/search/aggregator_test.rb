# frozen_string_literal: true

require "test_helper"

class SearchAggregatorTest < ActiveSupport::TestCase
  test "dedup canonicalizes utm_* и gclid/fbclid" do
    # Что проверяем:
    # - один и тот же URL с tracking-параметрами считается одним кандидатом
    # - дедуп происходит по canonicalized URL

    r1 = Search::SearchResult.new(
      url: "https://example.com/page?utm_source=abc&gclid=1",
      title: "t1",
      snippet: "s1",
      provider: "serper",
      raw: {}
    )

    r2 = Search::SearchResult.new(
      url: "https://example.com/page?gclid=999&utm_medium=cpc",
      title: "t2",
      snippet: "s2",
      provider: "tavily",
      raw: {}
    )

    deduped = Search::Aggregator.dedup([r1, r2])
    assert_equal 1, deduped.size
    assert_equal "https://example.com/page", deduped.first.url
  end
end

