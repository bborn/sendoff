module Sendoff
  module Mcp
    class ListDraftsTool < BaseTool
      tool_name "list_drafts"
      description "List drafts, optionally filtered by status. Returns summary + body_preview (first 400 chars). Call get_draft(id) for full body and metadata."

      input_schema(
        properties: {
          status: { type: "string", description: "Filter by status: pending, sending, scheduled, sent, flagged, discarded. Omit for all." },
          limit: { type: "integer", description: "Max results (default 25, max 100)" }
        }
      )

      class << self
        def perform(status: nil, limit: 25, **_)
          limit = [ limit.to_i, 100 ].min
          limit = 25 if limit < 1

          scope = Sendoff::Draft.includes(:email_account, lead: :company)
          scope = scope.where(status: status) if status.present? && Sendoff::Draft.statuses.key?(status)
          drafts = scope.order(created_at: :desc).limit(limit)

          results = drafts.map do |d|
            body_text = d.body_html.to_s.gsub(%r{</p>}, "\n\n").gsub(/<[^>]+>/, "").gsub(/\n{3,}/, "\n\n").strip
            {
              id: d.id,
              lead_email: d.to_addr,
              lead_name: d.lead&.display_name,
              company: d.lead&.company&.name,
              from: d.email_account&.email,
              subject: d.subject,
              status: d.status,
              intent: d.intent,
              cc_addr: d.cc_addr,
              bcc_addr: d.bcc_addr,
              body_preview: body_text.first(400),
              human_edited: d.human_edited,
              created_at: d.created_at,
              scheduled_at: d.scheduled_at,
              sent_at: d.sent_at
            }
          end

          text_response({ ok: true, count: results.size, drafts: results })
        end
      end
    end
  end
end
