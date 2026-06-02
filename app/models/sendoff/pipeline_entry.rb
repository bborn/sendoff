module Sendoff
  class PipelineEntry < ApplicationRecord
    # scopes: false prevents the `new` stage scope from colliding with
    # ActiveRecord::Base.new.
    enum :stage, {
      new: "new",
      drafting: "drafting",
      review: "review",
      contacted: "contacted",
      replied: "replied",
      dud: "dud"
    }, validate: true, scopes: false

    # When the stage moves to "drafting", enqueue a DraftJob with :auto intent.
    # The Drafter picks the actual intent (cold/reengage/checkin/followup).
    STAGE_TO_DRAFT_INTENT = {
      "drafting" => { intent: :auto, advance_to_stage: nil }
    }.freeze

    # Stages from which the entry must never regress. Activity fields may still
    # be refreshed, but callers should not move the stage backwards out of these.
    PROTECTED_STAGES = %w[replied dud].freeze

    belongs_to :lead
    belongs_to :company
    has_many :drafts, dependent: :destroy
    has_many :notes, as: :notable, dependent: :destroy

    validates :stage, presence: true
    validate :no_regression_from_protected_stage

    after_update_commit :enqueue_draft_on_stage_change, if: :saved_change_to_stage?
    after_create_commit :enqueue_draft_on_initial_stage

    # Thread-local switch to disable the auto-DraftJob enqueue for the duration of
    # a block. Used by ETL/import paths that set the stage from upstream data and
    # must NOT fire a real draft as a side-effect.
    def self.skip_draft_callbacks
      Thread.current[:sendoff_pipeline_entry_skip_draft_callbacks] = true
      yield
    ensure
      Thread.current[:sendoff_pipeline_entry_skip_draft_callbacks] = false
    end

    def self.skip_draft_callbacks?
      Thread.current[:sendoff_pipeline_entry_skip_draft_callbacks] == true
    end

    def stage_label
      stage&.humanize || "Unknown"
    end

    # Generic warmth signal accessor over the `signals` jsonb (replaces a
    # host-specific flag in the original app). A truthy value under any key marks
    # the lead as warm.
    def warm_signal?
      signals.is_a?(Hash) && signals.values.any? { |v| v.present? && v != false }
    end

    private

    def no_regression_from_protected_stage
      return unless stage_changed?
      previous = stage_was
      return unless PROTECTED_STAGES.include?(previous)
      return if previous == stage
      errors.add(:stage, "cannot regress out of protected stage '#{previous}'")
    end

    def enqueue_draft_on_stage_change
      return if self.class.skip_draft_callbacks?
      cfg = STAGE_TO_DRAFT_INTENT[stage]
      return unless cfg
      # DraftJob is provided by the jobs layer. Guard so the foundation specs
      # don't require it to be defined.
      return unless defined?(Sendoff::DraftJob)
      Sendoff::DraftJob.perform_later(id, intent: cfg[:intent], advance_to_stage: cfg[:advance_to_stage])
    end

    def enqueue_draft_on_initial_stage
      enqueue_draft_on_stage_change
    end
  end
end
