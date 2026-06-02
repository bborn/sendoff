module Sendoff
  module Mcp
    class QueueDraftTool < BaseTool
      tool_name "queue_draft"
      description "Triggers the Drafter (auto intent) for a lead. Runs synchronously and returns the resulting draft_id. Pass 'from' to override sender mailbox."

      input_schema(
        properties: {
          lead_id: { type: "string", description: "Lead UUID or email address" },
          from:    { type: "string", description: "Optional sender email address. Must match an active EmailAccount. If omitted, the Drafter picks based on prior thread history." }
        },
        required: [ "lead_id" ]
      )

      class << self
        def perform(lead_id:, from: nil, **_)
          lead = find_lead(lead_id)

          account = nil
          if from.present?
            account = Sendoff::EmailAccount.active.find_by("LOWER(email) = ?", from.to_s.downcase)
            return text_response({ ok: false, error: "Sender '#{from}' is not an active EmailAccount" }) unless account
          end

          entry = Sendoff::PipelineEntry.where(lead: lead).order(updated_at: :desc).first
          if entry.nil?
            Sendoff::PipelineEntry.skip_draft_callbacks do
              entry = Sendoff::PipelineEntry.create!(lead: lead, company: lead.company, stage: "new")
            end
          end

          pre_count = Sendoff::Draft.where(pipeline_entry: entry).count

          # Prefer the jobs layer when present (handles persistence + Gmail preview).
          # Fall back to the Drafter service so the tool works before DraftJob lands.
          if defined?(Sendoff::DraftJob)
            Sendoff::DraftJob.perform_now(entry.id, intent: :auto, email_account_email: from)
          else
            run_drafter_inline(lead, entry, account)
          end

          draft = Sendoff::Draft.where(pipeline_entry: entry).order(created_at: :desc).first

          if draft && Sendoff::Draft.where(pipeline_entry: entry).count > pre_count
            audit_write!(action: "mcp_queue_draft", subject: draft,
                         detail: "lead=#{lead.email} entry=#{entry.id} from=#{from}")
            text_response({
              ok: true,
              draft_id: draft.id,
              subject: draft.subject,
              status: draft.status,
              from: draft.email_account&.email
            })
          else
            text_response({ ok: false, error: "Draft was not created (lead may have been skipped by the Drafter)", entry_id: entry.id })
          end
        end

        private

        # Minimal inline persistence path used only when the jobs layer
        # (Sendoff::DraftJob) is not loaded.
        def run_drafter_inline(lead, entry, account)
          result = Sendoff::Drafter.draft_for_lead(lead, intent: :auto, email_account: account)
          return if result.skip?

          Sendoff::Draft.create!(
            lead: lead,
            pipeline_entry: entry,
            email_account: result.email_account || account,
            to_addr: lead.email,
            subject: result.subject,
            body_html: result.body_html,
            status: "pending",
            intent: result.intent,
            gmail_thread_id: result.thread_id,
            prompt_used: result.prompt_used,
            raw_response: result.raw_response,
            flagged_claims: result.flagged_claims,
            name_confidence: result.name_confidence
          )
        end
      end
    end
  end
end
