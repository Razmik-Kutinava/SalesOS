# frozen_string_literal: true

module Search
  SearchResult = Data.define(:url, :title, :snippet, :provider, :raw) # raw: provider payload fragment

  VerifiedSelection = Data.define(
    :candidate_urls, # [{url:, reason:, confidence:, needs_playwright_confirmation:}]
    :needs_manual_review, # boolean
    :selection_reason # string
  )

  VerifiedPages = Data.define(
    :approved_sources, # [{url:, confidence:, extracted_fields:, reason:}]
    :rejected_sources, # [{url:, reason:}]
    :lead_updates, # { company_name:, email:, phone:, contact_name:, stage: } (optional)
    :outcome_summary, # string
    :what_to_do_options, # [{title:, description:}] optional for UI/voice
    :needs_manual_review, # boolean
    :verification_reason # string
  )
end

