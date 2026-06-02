module Sendoff
  module Mcp
    class RefineDraftTool < BaseTool
      tool_name "refine_draft"
      description "Re-runs the Drafter with feedback to revise a draft. Optionally adds the feedback as a permanent voice rule. Pass 'from' to switch sender mailbox."

      input_schema(
        properties: {
          draft_id:     { type: "string",  description: "Draft UUID" },
          feedback:     { type: "string",  description: "Revision instructions (e.g. 'Make it shorter', 'Never mention pricing'). Required." },
          from:         { type: "string",  description: "Optional sender email override. Must match an active EmailAccount." },
          apply_to_all: { type: "boolean", description: "If true, also save the feedback as a voice rule for all future drafts" }
        },
        required: %w[draft_id feedback]
      )

      class << self
        def perform(draft_id:, feedback:, from: nil, apply_to_all: false, **_)
          draft = Sendoff::Draft.find(draft_id)
          feedback = feedback.to_s.strip
          return text_response({ ok: false, error: "Feedback cannot be blank" }) if feedback.blank?

          new_account = nil
          if from.present?
            new_account = Sendoff::EmailAccount.active.find_by("LOWER(email) = ?", from.to_s.downcase)
            return text_response({ ok: false, error: "Sender '#{from}' is not an active EmailAccount" }) unless new_account
          end

          revised = Sendoff::Drafts::Refiner.call(draft, feedback: feedback, email_account: new_account)
          draft.reload

          if apply_to_all
            Sendoff::VoiceRule.create!(
              scope: "all",
              rule: feedback.first(500),
              raw_feedback: feedback,
              source_draft_subject: draft.subject,
              source_recipient: draft.to_addr,
              created_by: "mcp"
            )
          end

          audit_write!(action: "mcp_refine_draft", subject: draft,
                       detail: "feedback=#{feedback.first(200)} apply_to_all=#{apply_to_all} from=#{from}")

          revised_hash = revised.respond_to?(:to_h) ? revised.to_h.symbolize_keys : revised

          text_response({
            ok: true,
            draft_id: draft.id,
            subject: revised_hash[:subject] || draft.subject,
            body_preview: (revised_hash[:body_html] || draft.body_html).to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip.first(300),
            from: draft.email_account&.email,
            cc_addr: draft.cc_addr,
            voice_rule_added: apply_to_all
          })
        end
      end
    end
  end
end
