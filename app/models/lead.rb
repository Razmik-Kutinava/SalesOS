class Lead < ApplicationRecord
  STAGES = %w[new qualified proposal negotiation won lost].freeze
  SOURCES = %w[import voice manual telegram].freeze

  belongs_to :account
  belongs_to :owner, class_name: "User", optional: true
  has_many :lead_events, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :lead_documents, dependent: :destroy
  has_many :voice_sessions, dependent: :nullify
  has_many :pending_actions, dependent: :destroy

  validates :stage, inclusion: { in: STAGES }
  validates :source, inclusion: { in: SOURCES }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :kept, -> { where(discarded_at: nil) }
end
