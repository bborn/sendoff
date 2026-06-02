module Sendoff
  class EmailEvent < ApplicationRecord
    enum :direction, { inbound: "inbound", outbound: "outbound" }, validate: true

    belongs_to :lead, optional: true
    belongs_to :company, optional: true
    belongs_to :email_account, optional: true

    validates :direction, presence: true
    validates :from_addr, presence: true
    validates :sent_at, presence: true
  end
end
