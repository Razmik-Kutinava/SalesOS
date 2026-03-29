class LeadEvent < ApplicationRecord
  belongs_to :lead
  belongs_to :actor, polymorphic: true, optional: true

  validates :event_type, presence: true
end
