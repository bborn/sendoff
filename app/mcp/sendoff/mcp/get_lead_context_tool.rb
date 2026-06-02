module Sendoff
  module Mcp
    class GetLeadContextTool < BaseTool
      tool_name "get_lead_context"
      description "Returns the full lead context the Drafter sees: lead, company, account, email thread history, domain history, voice rules, and notes."

      input_schema(
        properties: {
          email: { type: "string", description: "Lead email address (or lead_id UUID)" },
          intent: { type: "string", description: "Intent to use for context (cold, reengage, checkin, followup). Defaults to cold." }
        },
        required: [ "email" ]
      )

      class << self
        VALID_INTENTS = %w[cold reengage checkin followup].freeze

        def perform(email:, intent: "cold", **_)
          lead = find_lead(email)
          resolved_intent = intent.to_s.strip.presence_in(VALID_INTENTS) || "cold"

          ctx = Sendoff::Drafter::Context.new(lead, intent: resolved_intent.to_sym).build

          pipeline_entry = Sendoff::PipelineEntry.where(lead: lead).order(updated_at: :desc).first
          recent_notes = Sendoff::Note.where(notable: lead).order(created_at: :desc).limit(5).map do |n|
            { id: n.id, title: n.title, body: n.body_md, created_at: n.created_at }
          end

          text_response({
            ok: true,
            lead: ctx[:lead],
            company: ctx[:company],
            account: ctx[:account],
            pipeline_stage: pipeline_entry&.stage,
            pipeline_entry_id: pipeline_entry&.id,
            thread_history: ctx[:thread_history],
            domain_thread_history: ctx[:domain_thread_history],
            days_since_last_contact: ctx[:days_since_last_contact],
            reports_viewed: ctx[:reports_viewed],
            voice_rules: ctx[:voice_rules],
            company_notes: ctx[:company_notes],
            lead_notes: recent_notes,
            intent: resolved_intent
          })
        end
      end
    end
  end
end
