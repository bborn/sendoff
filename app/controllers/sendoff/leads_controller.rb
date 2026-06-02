module Sendoff
  class LeadsController < ApplicationController
    PER_PAGE = 50

    # GET /leads — browse table with segment / has-pipeline / free-text filters.
    def index
      scope = filter_scope

      @total = scope.count
      @page  = [ params[:page].to_i, 1 ].max
      @leads = scope
                 .order("sendoff_leads.created_at DESC")
                 .limit(PER_PAGE)
                 .offset((@page - 1) * PER_PAGE)
                 .includes(:company, :pipeline_entries)
                 .to_a

      @has_prev = @page > 1
      @has_next = (@page * PER_PAGE) < @total
    end

    # GET /leads/:id — full-page lead detail.
    def show
      @lead    = Lead.includes(:company).find(params[:id])
      @company = @lead.company
      @entry   = @lead.pipeline_entries.order(updated_at: :desc).first
      @notes   = @lead.notes.order(created_at: :desc)
      @pending_draft = @lead.drafts.where(status: "pending").order(created_at: :desc).first
      @gmail_history = safe_gmail_history(@lead)
    end

    # POST /leads/:id/enrich — force async re-enrichment.
    def enrich
      lead = Lead.find(params[:id])
      EnrichJob.perform_later(lead.id, force: true)
      AuditLog.record!(action: "enrich_queued", subject: lead, recipient: lead.email, detail: "force=true")

      respond_with_action(lead, "Enrichment queued for #{lead.display_name}.")
    end

    # POST /leads/:id/queue — move the pipeline entry to "drafting" so DraftJob runs.
    def queue
      lead  = Lead.find(params[:id])
      entry = PipelineEntry.find_or_initialize_by(lead: lead)
      entry.company = lead.company
      entry.stage   = "drafting"
      entry.queued_at = Time.current
      entry.save!

      AuditLog.record!(action: "lead_queued", subject: lead, recipient: lead.email, detail: "stage=drafting")

      respond_with_action(lead, "Draft queued for #{lead.display_name}.")
    end

    # POST /leads/:id/skip — hide the lead from suggestions.
    def skip
      lead = Lead.find(params[:id])
      HiddenLead.find_or_create_by!(lead: lead) do |h|
        h.hidden_by = Current.actor
        h.reason    = params[:reason].presence || "skipped"
      end
      AuditLog.record!(action: "lead_skipped", subject: lead, recipient: lead.email)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("lead-row-#{lead.id}"),
            toast_stream("Skipped #{lead.display_name}.")
          ]
        end
        format.html { redirect_back fallback_location: leads_path, notice: "Skipped #{lead.display_name}." }
      end
    end

    # POST /leads/:id/unskip — restore a hidden lead.
    def unskip
      lead = Lead.find(params[:id])
      lead.hidden_lead&.destroy!
      AuditLog.record!(action: "lead_unskipped", subject: lead, recipient: lead.email)

      respond_with_action(lead, "Restored #{lead.display_name}.")
    end

    private

    def filter_scope
      scope = Lead.all
      segment = params[:segment].to_s
      query   = params[:q].to_s.strip

      if segment.present? && Company.segments.key?(segment)
        scope = scope.joins(:company).where(sendoff_companies: { segment: segment })
      end

      case params[:has_pipeline]
      when "yes" then scope = scope.joins(:pipeline_entries).distinct
      when "no"  then scope = scope.where.missing(:pipeline_entries)
      end

      if query.present?
        q = "%#{query.downcase}%"
        scope = scope.where(
          "LOWER(sendoff_leads.email) LIKE :q OR " \
          "LOWER(sendoff_leads.first_name) LIKE :q OR " \
          "LOWER(sendoff_leads.last_name) LIKE :q OR " \
          "LOWER(sendoff_leads.full_name) LIKE :q",
          q: q
        )
      end

      scope
    end

    # Gmail::History hits the configured Gmail client. In dev/demo there are no
    # creds, so never let the detail page 500 — degrade to an empty result.
    def safe_gmail_history(lead)
      Sendoff::Gmail::History.for_lead(lead)
    rescue => e
      Rails.logger.warn "[Sendoff::LeadsController] gmail history failed for lead=#{lead.id}: #{e.message}"
      { messages: [], timed_out: [] }
    end

    def respond_with_action(lead, message)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: toast_stream(message) }
        format.html { redirect_back fallback_location: lead_path(lead), notice: message }
      end
    end

    def toast_stream(message)
      turbo_stream.append("toast-container") do
        view_context.content_tag(:div, message, class: "toast", data: { toast: "" })
      end
    end
  end
end
