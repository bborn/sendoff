require "json"

module Sendoff
  class Drafter
    # Second-pass LLM that rewrites AI tells out of a draft (subject + body).
    #
    # The first-pass Drafter writes the email. The Critic reads it against the
    # persona's voice rules + concrete BAD/GOOD pairs, then rewrites anything
    # that sounds like AI or marketing copy. Returns clean subject and body_html.
    #
    # Generic: the sender name and product name come from Sendoff.config.persona,
    # voice rules from Sendoff::VoiceRule.
    class VoiceCritic
      # Raised when the polished body still contains a brand-mention claim but
      # brand_mentions_count is 0 — the LLM made an unverifiable claim.
      class UnverifiedBrandMentionClaim < StandardError; end

      BRAND_MENTION_CLAIM_RE = /(?:people|creators?|folks|users?)\s+(?:in\s+our\s+network\s+)?(?:posting|talking)\s+about/i

      Result = Struct.new(:subject, :body_html, keyword_init: true)

      # Two call signatures supported:
      #   VoiceCritic.call(html)                      # body-only legacy
      #   VoiceCritic.call(subject:, body_html:)      # full pair
      # Optional: brand_mentions_count: Integer for postflight gate.
      def self.call(*args, **kwargs)
        if kwargs.any? || args.empty?
          new(subject: kwargs[:subject], body_html: kwargs[:body_html],
              voice_rules: kwargs[:voice_rules],
              brand_mentions_count: kwargs[:brand_mentions_count]).call
        else
          result = new(subject: nil, body_html: args.first.to_s,
                       voice_rules: kwargs[:voice_rules],
                       brand_mentions_count: kwargs[:brand_mentions_count]).call
          result.body_html
        end
      end

      def initialize(subject: nil, body_html: nil, voice_rules: nil, brand_mentions_count: nil)
        @subject              = subject.to_s
        @body_html            = body_html.to_s
        @voice_rules          = voice_rules
        @brand_mentions_count = brand_mentions_count
        @persona              = Sendoff.config.persona
      end

      def call
        return Result.new(subject: @subject, body_html: @body_html) if @body_html.strip.empty? && @subject.strip.empty?

        raw    = Sendoff.config.llm_client.complete(prompt)
        parsed = extract_pair(raw)

        result = Result.new(
          subject:   parsed[:subject].presence   || @subject,
          body_html: parsed[:body_html].presence || @body_html
        )

        postflight_brand_mention_check!(result.body_html)
        result
      rescue UnverifiedBrandMentionClaim
        raise
      rescue => e
        Rails.logger.warn("Sendoff::Drafter::VoiceCritic failed (returning original): #{e.class}: #{e.message}")
        Result.new(subject: @subject, body_html: @body_html)
      end

      private

      def postflight_brand_mention_check!(body_html)
        return unless @brand_mentions_count == 0

        text = body_html.to_s.gsub(/<[^>]+>/, " ")
        if text.match?(BRAND_MENTION_CLAIM_RE)
          raise UnverifiedBrandMentionClaim, "unverified_brand_mention_claim"
        end
      end

      def extract_pair(raw)
        json_str = raw.match(/```json\s*(\{.*?\})\s*```/m)&.captures&.first ||
                   raw.match(/\{[\s\S]*\}/)&.to_s ||
                   raw
        JSON.parse(json_str).transform_keys(&:to_sym)
      rescue JSON::ParserError
        { subject: @subject, body_html: @body_html }
      end

      def prompt
        sender  = @persona.sender_name
        product = @persona.product_name
        voice_rules = @voice_rules.presence ||
                      VoiceRule.where(scope: %w[all])
                               .pluck(:rule)
                               .then { |a| a.empty? ? "(none)" : a.map { |r| "- #{r}" }.join("\n") }

        <<~PROMPT
          You are a copy editor for #{product} emails. #{sender} is the sender; their voice is direct, warm, conversational, and never sounds like marketing copy. Your job: take the draft below (subject + body) and rewrite anything that reads like AI-generated marketing prose, while leaving everything that already sounds like #{sender} alone.

          ## #{sender}'s voice rules

          #{voice_rules}

          ## Hard rules for SUBJECTS specifically

          - Subjects must NEVER reference any internal routing signal (a page view, sign-up, download) or any internal data about the recipient.
          - Keep subjects 2-8 words, lowercase or sentence case (not Title Case), no em-dashes, no clickbait.
          - GOOD examples: "Quick question about your setup", "Reporting for your team", "Following up"
          - BAD examples: "Would love your take on X's report", "#{product} + Your Company", "Re: Your Workflow"

          ## Concrete BAD → GOOD body rewrites

          BAD:  Noticed you signed up for an account.
          GOOD: I noticed you signed up for an account.

          BAD:  Happy to walk you through it.
          GOOD: I'd be happy to walk you through it.

          BAD:  Worth knowing your account also gives you access to a few extras.
          GOOD: I wanted to make sure you know your account includes a few extras.

          BAD:  Saw you signed up recently. Welcome!
          GOOD: I saw you signed up recently. Welcome!

          BAD:  Hope this finds you well!
          GOOD: (delete entirely — never use this phrase)

          BAD:  Just a quick heads up that we shipped some new features.
          GOOD: I wanted to give you a quick heads up: we shipped some new features.

          BAD:  Make sure it's working for your team.   (when the lead has no team and a dormant account)
          GOOD: I noticed you signed up but it doesn't look like you've had a chance to use it yet.

          BAD:  That's totally fine.   (dry / clinical)
          GOOD: That's totally fine, I know things get busy!   (warm acknowledgment)

          ## Things to watch for in the body

          - Subject-less verb openers ("Noticed", "Saw", "Happy to", "Wanted to", "Hoping to", "Looking to", "Reaching out", "Worth knowing", "Quick heads up"). MUST start with a subject ("I noticed", "I wanted", "It's worth", etc.) at the start of any sentence or paragraph.
          - Em-dashes (—), en-dashes (–), or double-hyphens (--) used as separators. Replace with periods, commas, or natural connectors.
          - Comma-separated feature lists that read like a slide deck. Rewrite as natural prose.
          - SaaS phrases: "end to end", "stakeholders", "specifically built for", "industry-leading", "best-in-class".
          - "Hope this finds you well" or similar pleasantries — delete entirely.
          - Vague meeting offers ("happy to set up", "let me know when") without a calendar link.
          - "Make sure it's working" for accounts where the recipient has no team / dormant tenant.
          - Any reference to the recipient viewing pages, sessions, clicks, or product activity.
          - Dry one-line acknowledgments ("That's totally fine") — warm them up with empathy.

          ## Draft

          SUBJECT: #{@subject}

          BODY (HTML):
          #{@body_html}

          ## Output format — JSON only, no preamble

          ```json
          {
            "subject": "...",
            "body_html": "..."
          }
          ```

          If nothing needs changing, return the inputs verbatim in the same JSON shape. Preserve <p>, <br>, <a>, and other inline HTML tags in body_html.
        PROMPT
      end
    end
  end
end
