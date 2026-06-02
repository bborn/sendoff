require "json"

module Sendoff
  class Drafter
    # Postflight fact-checker: given the final body_html and the full context
    # hash that was fed to the Drafter, asks the LLM whether any specific
    # factual claim in the email (numbers, names, dates, specific events) is
    # NOT directly supported by the context.
    #
    # Returns a Result with ok: true (all claims backed) or ok: false with the
    # offending spans quoted. Never blocks sending — on any LLM error it passes
    # through with ok: true and logs a warning.
    #
    # Controlled by Sendoff.config.hallucination_critic_enabled (default true).
    class HallucinationCritic
      Result = Struct.new(:ok, :flagged_claims, :reason, keyword_init: true) do
        def ok? = ok
      end

      def self.call(body_html:, context:)
        new(body_html: body_html, context: context).call
      end

      def initialize(body_html:, context:)
        @body_html = body_html.to_s
        @context   = context || {}
      end

      def call
        return pass if disabled? || @body_html.strip.empty?

        raw    = Sendoff.config.llm_client.complete(prompt)
        parsed = parse_result(raw)
        claims = Array(parsed[:flagged_claims]).reject(&:blank?)

        if claims.any?
          Result.new(ok: false, flagged_claims: claims, reason: parsed[:reason].to_s)
        else
          pass
        end
      rescue => e
        Rails.logger.warn("[Sendoff::Drafter::HallucinationCritic] failed (passing through): #{e.class}: #{e.message}")
        pass
      end

      private

      def pass
        Result.new(ok: true, flagged_claims: [], reason: nil)
      end

      def disabled?
        !Sendoff.config.hallucination_critic_enabled
      end

      def parse_result(raw)
        json_str = raw.match(/```json\s*(\{.*?\})\s*```/m)&.captures&.first ||
                   raw.match(/\{[\s\S]*\}/)&.to_s ||
                   raw
        JSON.parse(json_str).transform_keys(&:to_sym)
      rescue JSON::ParserError
        { flagged_claims: [] }
      end

      def prompt
        <<~PROMPT
          You are a fact-checker for outbound sales emails. Given an email body and the supporting context that was available when it was written, identify any specific factual claim in the body that is NOT directly supported by the context.

          A "specific factual claim" means:
          - Numbers (e.g. "2 partners", "30% growth", "500 brands")
          - Named individuals, companies, or products attributed to the recipient
          - Specific dates or time references tied to the recipient (e.g. "you signed up last month")
          - Specific events attributed to the recipient (e.g. "you attended X", "you ran a campaign with Y")
          - Any concrete verifiable assertion about the recipient or their organization

          Do NOT flag:
          - General product feature descriptions ("helps you track campaigns")
          - Questions or hypotheticals ("would you be interested in…")
          - Offers and proposals ("happy to show you")
          - The product's own general capabilities that aren't recipient-specific

          Context provided to the email drafter:

          #{format_context}

          Email body (HTML):

          #{@body_html}

          Return JSON only, no preamble:
          - All claims supported: {"flagged_claims": [], "reason": null}
          - Any unsupported claim: {"flagged_claims": ["exact quoted text from the email body"], "reason": "brief explanation of what is missing from the context"}
        PROMPT
      end

      def format_context
        parts = []

        if (lead = @context[:lead]).present?
          parts << "### Lead\n#{lead.to_json}"
        end

        if (company = @context[:company]).present?
          parts << "### Company\n#{company.to_json}"
        end

        if (acct = @context[:account]).present?
          parts << "### Account\n#{account_to_h(acct).to_json}"
        end

        if (rv = @context[:reports_viewed]).present?
          parts << "### Reports Viewed\n#{rv.to_json}"
        end

        if (rs = @context[:research_summary]).present?
          parts << "### Research Summary\n#{rs}"
        end

        if (notes = @context[:company_notes]).present? && notes.any?
          parts << "### Company Notes\n#{notes.to_json}"
        end

        if (days = @context[:days_since_last_contact]).present?
          parts << "### Days Since Last Contact\n#{days}"
        end

        parts.empty? ? "(no context provided)" : parts.join("\n\n")
      end

      def account_to_h(acct)
        return acct unless acct.respond_to?(:to_h)
        acct.to_h.except(:metadata)
      end
    end
  end
end
