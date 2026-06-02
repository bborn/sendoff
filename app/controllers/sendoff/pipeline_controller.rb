module Sendoff
  class PipelineController < ApplicationController
    # Stage columns rendered left-to-right, mirroring the PipelineEntry enum.
    STAGE_ORDER = %w[new drafting review contacted replied dud].freeze

    STAGE_LABELS = {
      "new"       => "New",
      "drafting"  => "Drafting",
      "review"    => "Review",
      "contacted" => "Contacted",
      "replied"   => "Replied",
      "dud"       => "Dud"
    }.freeze

    def index
      scope = filter_scope

      counts = scope.group(:stage).count
      @stage_counts = STAGE_ORDER.each_with_object({}) { |s, h| h[s] = counts[s] || 0 }

      entries = scope.includes(lead: :company).order(updated_at: :desc).to_a
      @entries_by_stage = STAGE_ORDER.each_with_object({}) do |stage, hash|
        hash[stage] = entries.select { |e| e.stage == stage }
      end

      @stage_order  = STAGE_ORDER
      @stage_labels = STAGE_LABELS
      @show_duds    = params[:duds].present?
    end

    def move
      entry = PipelineEntry.find(params[:id])
      new_stage = params[:stage].to_s

      unless PipelineEntry.stages.key?(new_stage)
        render json: { error: "Unknown stage '#{new_stage}'" }, status: :unprocessable_entity
        return
      end

      previous_stage = entry.stage

      # Reject regressions out of protected stages (replied/dud) before touching
      # the record. The model validates this too, but we short-circuit with a
      # clear 422 message for the drag-drop client.
      if PROTECTED_REGRESSION_BLOCKED.call(previous_stage, new_stage)
        render json: {
          error: "Cannot move out of protected stage '#{previous_stage}'"
        }, status: :unprocessable_entity
        return
      end

      if entry.update(stage: new_stage)
        AuditLog.record!(
          action: "pipeline_stage_changed",
          subject: entry,
          recipient: entry.lead&.email,
          detail: "#{previous_stage} -> #{new_stage}"
        )
        head :ok
      else
        render json: { error: entry.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    private

    PROTECTED_STAGES = Sendoff::PipelineEntry::PROTECTED_STAGES

    # A move is blocked when leaving a protected stage for a different stage.
    PROTECTED_REGRESSION_BLOCKED = lambda do |from, to|
      PROTECTED_STAGES.include?(from) && from != to
    end

    def filter_scope
      scope = PipelineEntry.all
      segment = params[:segment].to_s
      query = params[:q].to_s.strip

      needs_company_join = (segment.present? && Company.segments.key?(segment)) || query.present?
      scope = scope.joins(:company) if needs_company_join
      scope = scope.joins(:lead) if query.present?

      if segment.present? && Company.segments.key?(segment)
        scope = scope.where(sendoff_companies: { segment: segment })
      end

      if query.present?
        q = "%#{query.downcase}%"
        scope = scope.where(
          "LOWER(sendoff_leads.full_name) LIKE :q OR " \
          "LOWER(sendoff_leads.first_name) LIKE :q OR " \
          "LOWER(sendoff_leads.last_name) LIKE :q OR " \
          "LOWER(sendoff_leads.email) LIKE :q OR " \
          "LOWER(sendoff_companies.name) LIKE :q",
          q: q
        )
      end

      scope
    end
  end
end
