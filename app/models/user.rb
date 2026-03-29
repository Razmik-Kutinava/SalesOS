class User < ApplicationRecord
  ROLES = %w[owner admin user].freeze

  belongs_to :account
  has_many :owned_leads, class_name: "Lead", foreign_key: :owner_id, inverse_of: :owner, dependent: :nullify
  has_many :tasks, foreign_key: :assignee_id, inverse_of: :assignee, dependent: :nullify
  has_many :voice_sessions, dependent: :destroy
  has_many :pending_actions, dependent: :destroy

  has_secure_password

  normalizes :email, with: ->(e) { e.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :account_id }
  validates :role, inclusion: { in: ROLES }
  validates :locale, presence: true
  validates :timezone, presence: true
  validates :telegram_id, uniqueness: { allow_nil: true }
end
