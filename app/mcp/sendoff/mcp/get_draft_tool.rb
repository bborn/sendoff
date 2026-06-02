module Sendoff
  module Mcp
    class GetDraftTool < BaseTool
      tool_name "get_draft"
      description "Returns the full draft: subject, body_html, recipients, intent, status, prompt sent to the LLM, raw response, and linked lead/company."

      input_schema(
        properties: {
          draft_id: { type: "string", description: "Draft UUID" }
        },
        required: [ "draft_id" ]
      )

      class << self
        def perform(draft_id:, **_)
          d = Sendoff::Draft.includes(:email_account, :pipeline_entry, lead: :company).find_by(id: draft_id)
          return text_response({ ok: false, error: "Draft not found: #{draft_id}" }) unless d

          text_response({
            ok: true,
            draft: {
              id: d.id,
              status: d.status,
              intent: d.intent,
              subject: d.subject,
              body_html: d.body_html,
              body_text: d.body_html.to_s.gsub(%r{</p>}, "\n\n").gsub(/<[^>]+>/, "").gsub(/\n{3,}/, "\n\n").strip,
              to_addr: d.to_addr,
              cc_addr: d.cc_addr,
              bcc_addr: d.bcc_addr,
              from: {
                email: d.email_account&.email,
                display_name: d.email_account&.display_name
              },
              gmail_draft_id: d.gmail_draft_id,
              gmail_thread_id: d.gmail_thread_id,
              scheduled_at: d.scheduled_at,
              sent_at: d.sent_at,
              send_job_id: d.send_job_id,
              human_edited: d.human_edited,
              original_subject: d.original_subject,
              original_body_html: d.original_body_html,
              prompt_used: d.prompt_used,
              raw_response: d.raw_response,
              flagged_claims: d.flagged_claims,
              name_confidence: d.name_confidence,
              created_at: d.created_at,
              updated_at: d.updated_at,
              lead: {
                id: d.lead.id,
                email: d.lead.email,
                name: d.lead.display_name
              },
              company: {
                id: d.lead.company&.id,
                name: d.lead.company&.name,
                domain: d.lead.company&.domain
              },
              pipeline_entry: d.pipeline_entry && {
                id: d.pipeline_entry.id,
                stage: d.pipeline_entry.stage
              }
            }
          })
        end
      end
    end
  end
end
