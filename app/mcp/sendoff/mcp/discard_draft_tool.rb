module Sendoff
  module Mcp
    class DiscardDraftTool < BaseTool
      tool_name "discard_draft"
      description "Discards a draft: marks it as discarded, deletes the Gmail draft if one exists, and resets the pipeline entry stage."

      input_schema(
        properties: {
          draft_id: { type: "string", description: "Draft UUID" }
        },
        required: [ "draft_id" ]
      )

      class << self
        def perform(draft_id:, **_)
          draft = Sendoff::Draft.find(draft_id)

          delete_gmail_draft(draft)

          draft.update!(status: :discarded, send_job_id: nil)

          # Reset the pipeline entry stage so the kanban isn't lying: an entry left
          # in 'review'/'drafting' with no live draft diverges from reality.
          if (entry = draft.pipeline_entry) && entry.stage.in?(%w[review drafting])
            Sendoff::PipelineEntry.skip_draft_callbacks do
              entry.update_columns(stage: "new", claimed_until: nil, updated_at: Time.current)
            end
          end

          audit_write!(action: "mcp_discard_draft", subject: draft,
                       recipient: draft.to_addr, detail: "discarded via Mcp; entry reset to new")

          text_response({ ok: true, draft_id: draft.id, status: draft.status })
        end

        private

        def delete_gmail_draft(draft)
          return if draft.gmail_draft_id.blank?
          client = Sendoff.config.gmail_client_for(draft.email_account)
          client.delete_draft(draft.gmail_draft_id)
        rescue => e
          Rails.logger.warn("[Sendoff::Mcp] discard_draft: failed to delete Gmail draft: #{e.message}")
        end
      end
    end
  end
end
