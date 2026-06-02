module Sendoff
  class EmailAccount < ApplicationRecord
    encrypts :oauth_refresh_token

    enum :role, { outreach: "outreach", personal: "personal", shared: "shared" }, validate: true

    has_many :drafts, dependent: :restrict_with_error
    has_many :email_events, dependent: :nullify

    scope :active, -> { where(active: true) }
    scope :for_outreach, -> { active.where(role: %w[outreach shared]) }

    validates :email, presence: true, uniqueness: true,
                      format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :display_name, presence: true

    before_validation :default_first_name

    def to_s
      "#{display_name} <#{email}>"
    end

    # OAuth client id/secret fall back to global ENV when not set per-account.
    def resolved_client_id
      oauth_client_id.presence || ENV["GMAIL_OAUTH_CLIENT_ID"]
    end

    def resolved_client_secret
      oauth_client_secret.presence || ENV["GMAIL_OAUTH_CLIENT_SECRET"]
    end

    private

    def default_first_name
      self.first_name ||= display_name.to_s.split(" ").first
    end
  end
end
