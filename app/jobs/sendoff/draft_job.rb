module Sendoff
  # Drafts an email for a pipeline entry using the agentic Drafter, then creates
  # a Gmail draft on the chosen EmailAccount. Triggered by PipelineEntry
  # callbacks (after_update_commit) when the stage changes to "drafting" — that
  # callback references this class by name.
  class DraftJob < Sendoff::ApplicationJob
    queue_as :default

    # When intent is :auto, the LLM picks the intent; all intents advance to "review".
    INTENT_TO_ADVANCE_STAGE = {
      "cold"     => "review",
      "reengage" => "review",
      "checkin"  => "review",
      "followup" => "review"
    }.freeze

    # intent: :auto | :cold | :reengage | :checkin | :followup
    # advance_to_stage: optional stage to set on the entry after the draft is
    #   created. Ignored for :auto intent (determined by result.intent via
    #   INTENT_TO_ADVANCE_STAGE).
    # email_account_email: optional override; pick this active EmailAccount as
    #   sender instead of letting Drafter#pick_email_account choose.
    def perform(pipeline_entry_id, intent:, advance_to_stage: nil, email_account_email: nil)
      entry = PipelineEntry.find_by(id: pipeline_entry_id)
      return unless entry

      explicit_account = nil
      if email_account_email.present?
        explicit_account = EmailAccount.active.find_by("LOWER(email) = ?", email_account_email.downcase)
        unless explicit_account
          Rails.logger.warn "[Sendoff::DraftJob] requested sender #{email_account_email} not found / inactive — falling back to auto-pick"
        end
      end

      result = Drafter.draft_for_lead(entry.lead, intent: intent.to_sym, email_account: explicit_account)

      return handle_skip(entry, intent, result) if result.skip?

      # For :auto intent, the LLM returned the resolved intent; use it for stage advancement.
      resolved_intent = result.intent&.to_s || intent.to_s
      effective_advance = if intent.to_sym == :auto
        INTENT_TO_ADVANCE_STAGE[resolved_intent]
      else
        advance_to_stage
      end

      account = result.email_account
      gmail_draft_id = Sendoff.config.gmail_client_for(account).create_draft(
        to: entry.lead.email,
        subject: result.subject,
        body_html: result.body_html,
        thread_id: result.thread_id
      )

      draft = Draft.create!(
        lead: entry.lead,
        pipeline_entry: entry,
        email_account: account,
        to_addr: entry.lead.email,
        cc_addr: default_cc,
        bcc_addr: default_bcc,
        subject: result.subject,
        body_html: result.body_html,
        original_subject: result.subject,
        original_body_html: result.body_html,
        gmail_draft_id: gmail_draft_id,
        gmail_thread_id: result.thread_id,
        intent: resolved_intent,
        status: "pending",
        prompt_used: result.prompt_used,
        raw_response: result.raw_response,
        flagged_claims: result.flagged_claims.presence,
        name_confidence: result.name_confidence
      )

      if draft.hallucination_flagged?
        Rails.logger.warn "[Sendoff::DraftJob] hallucination critic flagged claims on draft=#{draft.id}: #{draft.flagged_claims.inspect}"
        AuditLog.record!(action: "hallucination_flagged", subject: draft,
                         detail: "claims=#{draft.flagged_claims.to_json}")
      end

      entry.update!(stage: effective_advance) if effective_advance

      AuditLog.record!(action: "drafted", subject: draft, email_account: account,
                       detail: "intent=#{resolved_intent} (requested=#{intent}) subject=#{result.subject.inspect}")

      Rails.logger.info "[Sendoff::DraftJob] drafted entry=#{entry.id} draft=#{draft.id} account=#{account.email} intent=#{resolved_intent}"
    end

    private

    # Persona-supplied default cc/bcc (drop the hardcoded founder CC / CRM BCC).
    def default_cc  = Array(Sendoff.config.persona.default_cc).first
    def default_bcc = Array(Sendoff.config.persona.default_bcc).first

    def handle_skip(entry, intent, result)
      Rails.logger.info "[Sendoff::DraftJob] skipped entry=#{entry.id} reason=#{result.skip_reason}"
      detail_extra = result.raw_response.present? ? "\nraw=#{result.raw_response.to_s.first(2000)}" : ""
      AuditLog.record!(action: "draft_skipped", subject: entry,
                       detail: "intent=#{intent} reason=#{result.skip_reason}#{detail_extra}")

      # Map specific skip reasons to terminal stages.
      #   recent_inbound_awaiting_response → "replied" (a manual response is owed)
      #   everything else → "dud" (filtered out / not worth contacting)
      target_stage = case result.skip_reason
      when "recent_inbound_awaiting_response" then "replied"
      else "dud"
      end

      if result.skip_reason == "competitor_adjacent"
        lead_domain = entry.lead.email.to_s.split("@", 2).last&.downcase
        cd = CompetitorDomain.find_by(domain: lead_domain)
        note_body = "auto-skipped: competitor (#{cd&.reason || lead_domain})"
        Note.create!(notable: entry.lead, body_md: note_body, author: "system", source: "draft_job")
      end

      PipelineEntry.skip_draft_callbacks do
        entry.update_columns(stage: target_stage, claimed_until: nil, updated_at: Time.current)
      end
      nil
    end
  end
end
