# frozen_string_literal: true

require "test_helper"

class VoiceGoldenPhrasesTest < ActiveSupport::TestCase
  test "LIST is non-empty and run_against_parser uses injected parser" do
    assert Voice::GoldenPhrases::LIST.size.positive?

    parser = Object.new
    def parser.call(transcript:, lead:, timezone:)
      { "intent" => "noop", "slots" => {}, "assistant_message" => "", "need_approval" => false }
    end

    results = Voice::GoldenPhrases.run_against_parser(lead: nil, parser: parser)
    assert_equal Voice::GoldenPhrases::LIST.size, results.size
    assert results.all? { |r| r[:parsed].is_a?(Hash) }
  end
end
