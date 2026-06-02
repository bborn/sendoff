require "json"

module Sendoff
  module Drafts
    # Revises a draft per human feedback via the configured LLM, re-runs the
    # voice critic, and (when the feedback is rule-like) distills + persists a
    # new VoiceRule. Can also switch the draft to a different sending mailbox,
    # rebuilding the Gmail preview draft and logging the change.
    #
    # All host-specific behavior is routed through Sendoff.config:
    #   - LLM        -> config.llm_client.complete(prompt)
    #   - gmail      -> config.gmail_client_for(account)
    #   - default cc -> config.persona.default_cc
    #   - actor      -> Sendoff::Current.actor_or_system
    class Refiner
      RULE_PREFIXES = [
        "always", "never", "avoid", "keep",
        "do not", "don't", "make sure", "ensure"
      ].freeze

      def self.call(draft, feedback:, email_account: nil)
        new(draft, email_account: email_account).call(feedback: feedback)
      end

      def initialize(draft, email_account: nil)
        @draft = draft
        @new_account = email_account
      end

      def call(feedback:)
        revised = revise_with_llm(feedback)

        # Refine produced new agent text. Reset the "original" baseline so later
        # edit-detection only triggers on HUMAN edits, not on this revision.
        @draft.update!(
          subject: revised[:subject],
          body_html: revised[:body_html],
          original_subject: revised[:subject],
          original_body_html: revised[:body_html],
          human_edited: false
        )

        # Sender swap after the content rewrite so the new Gmail preview carries
        # the revised body and the (LLM-rewritten) signature.
        switch_email_account! if @new_account && @new_account != @draft.email_account

        if rule_like?(feedback)
          rule_text = distill_rule_with_llm(feedback)
          VoiceRule.create!(
            scope: rule_scope,
            rule: rule_text,
            raw_feedback: feedback,
            source_draft_subject: @draft.subject,
            source_recipient: @draft.to_addr,
            created_by: Sendoff::Current.actor_or_system
          )
        end

        revised
      end

      private

      # VoiceRule scope must be one of VoiceRule::SCOPES. The draft intent isn't
      # a valid scope value, so default to "all" (a universal rule).
      def rule_scope
        "all"
      end

      def rule_like?(feedback)
        lower = feedback.to_s.downcase.strip
        RULE_PREFIXES.any? { |prefix| lower.start_with?(prefix) }
      end

      def revise_with_llm(feedback)
        sender_hint = if @new_account && @new_account != @draft.email_account
          "\nSENDER CHANGE: The email is being moved to a new mailbox (#{@new_account.email}, display name #{@new_account.display_name.inspect}). " \
          "Update the signature/sign-off to match the new sender (use their display name, not the previous one). " \
          "Remove any phrasing that only makes sense from the previous sender."
        else
          ""
        end

        prompt = <<~PROMPT
          You are editing an email per the user's feedback.

          CRITICAL FORMATTING RULES:
          - Return ONLY raw HTML (use real <p>, <ul><li>, <a>, <strong>, <br> tags). NEVER use markdown.
          - Preserve all URLs exactly. Apply ONLY the user's requested change.

          Return the revised email as JSON: {"subject": "...", "body_html": "..."}

          CURRENT SENDER: #{@draft.email_account&.email} (#{@draft.email_account&.display_name})
          CURRENT SUBJECT: #{@draft.subject}
          CURRENT BODY (HTML):
          #{@draft.body_html}

          USER FEEDBACK: #{feedback}#{sender_hint}

          Return ONLY valid JSON on a single line.
        PROMPT

        raw    = Sendoff.config.llm_client.complete(prompt)
        parsed = extract_json(raw)

        raw_subject = parsed["subject"].presence || @draft.subject
        raw_body    = parsed["body_html"].presence || @draft.body_html
        critiqued   = Drafter::VoiceCritic.call(subject: raw_subject, body_html: raw_body)
        {
          subject:   critiqued.subject,
          body_html: critiqued.body_html
        }
      end

      def switch_email_account!
        self.class.switch_account!(@draft, @new_account)
      end

      # Class-method form so send/refine flows can swap sender without going
      # through the Refiner LLM call. Idempotent if already on the target account.
      def self.switch_account!(draft, new_account)
        return if new_account.nil? || new_account == draft.email_account

        old_account = draft.email_account

        # Delete the old Gmail preview draft (best-effort — never block on this).
        if draft.gmail_draft_id && old_account
          begin
            Sendoff.config.gmail_client_for(old_account).delete_draft(draft.gmail_draft_id)
          rescue => e
            Rails.logger.warn("[Sendoff::Drafts::Refiner.switch_account!] delete old Gmail draft id=#{draft.gmail_draft_id} failed: #{e.class}: #{e.message}")
          end
        end

        # Create a fresh Gmail preview draft in the new mailbox. CRITICAL: do NOT
        # carry over draft.gmail_thread_id — that thread lives in the OLD mailbox.
        # On sender swap we lose thread continuity and send as a fresh email.
        new_gmail_draft_id =
          begin
            Sendoff.config.gmail_client_for(new_account).create_draft(
              to: draft.to_addr,
              subject: draft.subject,
              body_html: draft.body_html,
              thread_id: nil
            )
          rescue => e
            Rails.logger.error("[Sendoff::Drafts::Refiner.switch_account!] create new Gmail draft in #{new_account.email} failed: #{e.class}: #{e.message}")
            nil
          end

        # Default-CC from persona, unless the new sender IS the default CC.
        persona_cc = Array(Sendoff.config.persona.default_cc).first
        default_cc = (persona_cc unless persona_cc && new_account.email.casecmp?(persona_cc))

        draft.update!(
          email_account: new_account,
          gmail_draft_id: new_gmail_draft_id,
          gmail_thread_id: nil,
          cc_addr: default_cc
        )

        AuditLog.record!(
          action: "draft_sender_changed",
          subject: draft,
          email_account: new_account,
          detail: "from=#{old_account&.email} to=#{new_account.email}"
        )
      end

      def distill_rule_with_llm(feedback)
        prompt = "Distill this feedback into a single concise voice rule. " \
                 "One sentence, imperative ('Always X', 'Never Y'). " \
                 "Return ONLY valid JSON: {\"rule\": \"<rule text>\"}\n\n" \
                 "FEEDBACK: #{feedback}"
        raw    = Sendoff.config.llm_client.complete(prompt)
        parsed = extract_json(raw)
        parsed["rule"].presence || raw.to_s.strip.presence || feedback[0..199]
      rescue => e
        Rails.logger.error("Sendoff::Drafts::Refiner#distill_rule_with_llm: #{e.message}")
        feedback[0..199]
      end

      def extract_json(raw)
        match = raw.to_s.match(/\{.*\}/m)
        return {} unless match
        JSON.parse(match[0])
      rescue JSON::ParserError
        {}
      end
    end
  end
end
