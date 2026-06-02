module Sendoff
  class AuditLog < ApplicationRecord
    belongs_to :subject, polymorphic: true, optional: true
    belongs_to :email_account, optional: true

    def self.record!(action:, subject: nil, recipient: nil, email_account: nil, detail: nil)
      create!(actor: Current.actor_or_system, action: action, subject: subject,
              recipient: recipient, email_account: email_account, detail: detail,
              created_at: Time.current)
    end
  end
end
