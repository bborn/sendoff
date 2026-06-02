module Sendoff
  module Mcp
    class SendDraftTool < BaseTool
      tool_name "send_draft"
      description "Queues a pending or scheduled draft to send via Gmail. Returns the send status."

      input_schema(
        properties: {
          draft_id: { type: "string", description: "Draft UUID" }
        },
        required: [ "draft_id" ]
      )

      class << self
        def perform(draft_id:, **_)
          draft = Sendoff::Draft.includes(:email_account, lead: :company).find(draft_id)

          unless draft.pending? || draft.scheduled?
            return text_response({ ok: false, error: "Draft status is '#{draft.status}'; only pending or scheduled drafts can be sent" })
          end

          Sendoff::Drafts::Sender.call(draft)

          audit_write!(action: "mcp_send_draft", subject: draft,
                       recipient: draft.to_addr, detail: "status=queued")

          text_response({
            ok: true,
            draft_id: draft.id,
            status: "queued",
            to: draft.to_addr
          })
        rescue Sendoff::Drafts::RateLimitExceeded => e
          text_response({ ok: false, error: e.message, code: "rate_limit_exceeded" })
        end
      end
    end
  end
end
