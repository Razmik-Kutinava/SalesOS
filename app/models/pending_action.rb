class PendingAction < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :user
  belongs_to :lead

  validates :action_type, presence: true
  validates :status, inclusion: { in: STATUSES }
end
