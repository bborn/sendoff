module Sendoff
  module Mcp
    class SkipLeadTool < BaseTool
      tool_name "skip_lead"
      description "Hides a lead from the pipeline and cancels any pending drafts."

      input_schema(
        properties: {
          lead_id: { type: "string", description: "Lead UUID or email address" },
          reason: { type: "string", description: "Optional reason for skipping" }
        },
        required: [ "lead_id" ]
      )

      class << self
        def perform(lead_id:, reason: nil, **_)
          lead = find_lead(lead_id)

          Sendoff::HiddenLead.find_or_create_by!(lead: lead) do |hl|
            hl.hidden_by = "mcp"
            hl.reason = reason.to_s.presence
          end

          cancelled = Sendoff::Draft.where(lead: lead, status: :pending).update_all(status: "discarded")

          audit_write!(action: "mcp_skip_lead", subject: lead,
                       detail: "reason=#{reason.to_s.first(200)} drafts_cancelled=#{cancelled}")

          text_response({
            ok: true,
            lead_id: lead.id,
            email: lead.email,
            reason: reason,
            pending_drafts_cancelled: cancelled
          })
        end
      end
    end
  end
end
