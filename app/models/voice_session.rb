class VoiceSession < ApplicationRecord
  STATUSES = %w[pending recording processing done error].freeze

  belongs_to :user
  belongs_to :lead, optional: true

  validates :status, inclusion: { in: STATUSES }
end
