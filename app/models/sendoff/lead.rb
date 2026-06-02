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

    # name_source values that indicate the lead's name was NOT verified — it was
    # guessed from the email local-part or is altogether unknown. These are the
    # leads worth researching to recover a real name.
    WEAK_NAME_SOURCES = %w[email_prefix unknown].freeze

    # Title of the auto-generated note the enrichment job writes. Used to detect
    # whether this lead has already been researched.
    RESEARCH_NOTE_TITLE = "Research Summary (auto)".freeze

    # True when this lead is a good candidate for async enrichment.
    #
    # Enrichable when ALL of:
    #   - the name is weak — name_source is email_prefix/unknown, OR first_name
    #     is blank (so research can recover a real name), AND
    #   - no research note exists on the lead yet (don't re-research), AND
    #   - the lead is not hidden.
    #
    # Deliberately generic: no host-specific warmth/stage/domain concepts. The
    # research adapter itself decides what (if anything) to return; with the
    # default NullResearch adapter enrichment is a harmless no-op regardless.
    def enrichable?
      return false if hidden?
      return false unless weak_name?
      return false if research_note?

      true
    end

    private

    def weak_name?
      WEAK_NAME_SOURCES.include?(name_source.to_s) || first_name.blank?
    end

    def research_note?
      notes.where(title: RESEARCH_NOTE_TITLE).exists?
    end
  end
end
