module Sendoff
  class Draft < ApplicationRecord
    enum :status, {
      pending: "pending",
      sending: "sending",
      scheduled: "scheduled",
      sent: "sent",
      flagged: "flagged",
      discarded: "discarded"
    }, validate: true
    enum :intent, {
      cold: "cold",
      reengage: "reengage",
      checkin: "checkin",
      followup: "followup",
      auto: "auto"
    }, validate: { allow_nil: true }
    enum :name_confidence, {
      research_verified: "research_verified",
      email_prefix: "email_prefix",
      rescued_by_research: "rescued_by_research"
    }, validate: { allow_nil: true }, prefix: :name_confidence

    belongs_to :lead
    belongs_to :pipeline_entry, optional: true
    belongs_to :email_account, optional: true

    scope :pending_review, -> { where(status: "pending").order(created_at: :desc) }
    scope :hallucination_flagged, -> { where("flagged_claims IS NOT NULL AND jsonb_array_length(flagged_claims) > 0") }

    validates :to_addr, presence: true
    validates :subject, presence: true
    validates :body_html, presence: true
    validates :status, presence: true

    def hallucination_flagged?
      flagged_claims.present? && flagged_claims.any?
    end
  end
end
