class Task < ApplicationRecord
  STATUSES = %w[open done cancelled].freeze

  belongs_to :lead
  belongs_to :assignee, class_name: "User", optional: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
end
