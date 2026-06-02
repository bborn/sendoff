module Sendoff
  class Lead < ApplicationRecord
    attribute :name_source, :string
    enum :name_source, {
      manual: "manual",
      email_prefix: "email_prefix",
      enriched: "enriched",
      unknown: "unknown"
    }, validate: true

    belongs_to :company
    has_many :pipeline_entries, dependent: :destroy
    has_many :email_events, dependent: :nullify
    has_many :drafts, dependent: :destroy
    has_one :hidden_lead, dependent: :destroy
    has_many :notes, as: :notable, dependent: :destroy

    validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

    def display_name
      full_name.presence || first_name.presence || email
    end

    def hidden?
      hidden_lead.present?
    end

    # True when this lead is a good candidate for async enrichment.
    #
    # Skip if:
    #   - Latest pipeline stage is contacted / replied / dud (past prospecting)
    #   - A substantial note (> 300 chars) already exists on the lead or company
    #
    # Enrich if ALL:
    #   - Stage is new / drafting / review
    #   - warm_score >= 2 OR last_report_view within 90 days OR a warmth signal is set
    #   - No substantial pre-existing note
    #
    # TODO(seam): in the original app this personal/disposable-domain skiplist
    # lived in the lead sync service. The generic Leads::Sync service should own
    # any host-specific domain skip; this method intentionally does not hardcode one.
    def enrichable?
      pe = pipeline_entries.order(updated_at: :desc).first
      return false unless pe
      return false if pe.stage.in?(%w[contacted replied dud])

      warm = pe.warm_score.to_i >= 2 ||
             (pe.last_report_view.present? && pe.last_report_view >= 90.days.ago.to_date) ||
             pe.warm_signal?
      return false unless warm

      return false if notes.order(created_at: :desc).first&.body_md&.length.to_i > 300
      return false if company.notes.order(created_at: :desc).first&.body_md&.length.to_i > 300

      true
    end
  end
end
