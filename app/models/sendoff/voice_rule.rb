module Sendoff
  class VoiceRule < ApplicationRecord
    SCOPES = %w[all cold_prospect customer_success reengage_cold reengage_customer].freeze

    scope :active_rules, -> { where(active: true) }
    scope :for_scope, ->(s) { where(scope: s) }

    validates :scope, presence: true, inclusion: { in: SCOPES }
    validates :rule, presence: true
  end
end
