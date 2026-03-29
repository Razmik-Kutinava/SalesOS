class LeadDocument < ApplicationRecord
  belongs_to :lead

  has_one_attached :file

  validates :name, presence: true
  validates :kind, presence: true
end
