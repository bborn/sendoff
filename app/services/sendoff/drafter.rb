require "json"

module Sendoff
  # The core LLM email-drafting engine. Given a lead and an intent, assembles
  # context, prompts the configured LLM, runs the voice + hallucination critics,
  # validates URLs against the persona allowlist, and returns a Result.
  #
  # All host-specific behavior is routed through Sendoff.config:
  #   - LLM           -> config.llm_client.complete(prompt)
  #   - persona/voice -> config.persona
  #   - account info  -> config.account_lookup
  #   - brand signals -> config.brand_mention_source
  #   - gmail history  -> config.gmail_client_for (via Sendoff::Gmail::History)
  class Drafter
    Result = Struct.new(:subject, :body_html, :email_account, :thread_id, :name_used,
                        :intent, :skip_reason, :prompt_used, :raw_response, :flagged_claims,
                        :name_confidence, keyword_init: true) do
      def skip? = skip_reason.present?
    end

    attr_reader :prompt_used, :raw_response

    def self.draft_for_lead(lead, intent:, email_account: nil)
      new(lead, intent: intent, email_account: email_account).draft
    end

    # email_account: optional explicit account to draft as. If nil, picked from
    # context (most-recent prior thread's account, else first active outreach account).
    def initialize(lead, intent:, email_account: nil)
      @lead = lead
      @intent = intent.to_sym
      @explicit_email_account = email_account
    end

    def draft
      # Name unknown: lead.first_name is blank, or name_source is unreliable
      # (email_prefix = guessed from email; unknown = no signal). A verified
      # research name can still rescue us — the prompt embeds the research and
      # the LLM uses the verified name.
      if @lead.name_source.in?(%w[email_prefix unknown]) || @lead.first_name.blank?
        return skip("name_unknown") unless research_has_verified_name?
      end

      domain = @lead.email.to_s.split("@", 2).last&.downcase
      if Drafter::Prompt::PERSONAL_EMAIL_DOMAINS.include?(domain)
        return skip("personal_email")
      end

      if CompetitorDomain.exists?(domain: domain)
        return skip("competitor_adjacent")
      end

      # Skip when the lead replied to us recently — the ball is in our court
      # manually; auto-drafting another email would supersede the live thread.
      recent = Sendoff::Gmail::History.for_lead(@lead)[:messages].first
      if recent && recent[:direction].to_s == "inbound" && recent[:sent_at] &&
         (Date.today - recent[:sent_at].to_date).to_i < 30
        return skip("recent_inbound_awaiting_response")
      end

      ctx = Drafter::Context.new(@lead, intent: @intent).build
      chosen_account = pick_email_account(ctx)
      return skip("no_email_account_available") unless chosen_account

      # Hold off on cold-touching freshly-captured leads. Giving them a few days
      # of breathing room before the cold touch avoids the "I just gave you my
      # email and now you're pitching me" feeling. Does NOT apply to checkin
      # (they have an account) or reengage/followup (prior thread exists).
      if cold_eligible_intent?(@intent) &&
         @lead.created_at &&
         @lead.created_at > Sendoff.config.lead_fresh_touch_days.days.ago &&
         ctx[:account].blank? &&
         ctx[:thread_history].blank?
        return skip("lead_too_recent_first_touch")
      end

      prompt = Drafter::Prompt.new(ctx, email_account: chosen_account).build
      @prompt_used = prompt
      raw = call_llm(prompt)
      @raw_response = raw
      parsed = parse_output(raw)

      return skip(parsed[:skip_reason]) if parsed[:skip_reason].present?

      # When intent is :auto, the LLM returns the chosen intent in the JSON.
      resolved_intent = if @intent == :auto
        parsed[:intent]&.to_sym || :cold
      else
        @intent
      end

      begin
        critiqued = Drafter::VoiceCritic.call(
          subject: parsed[:subject].to_s,
          body_html: parsed[:body_html].to_s,
          brand_mentions_count: ctx[:brand_mentions_count]
        )
      rescue Drafter::VoiceCritic::UnverifiedBrandMentionClaim
        return skip("unverified_brand_mention_claim")
      end
      validate_urls!(critiqued.body_html, ctx)

      hallucination = Drafter::HallucinationCritic.call(body_html: critiqued.body_html, context: ctx)

      Result.new(
        subject: critiqued.subject,
        body_html: critiqued.body_html,
        email_account: chosen_account,
        thread_id: pick_thread_id(chosen_account, ctx, resolved_intent),
        name_used: parsed[:name_used].presence || @lead.first_name,
        intent: resolved_intent,
        skip_reason: nil,
        prompt_used: @prompt_used,
        raw_response: @raw_response,
        flagged_claims: hallucination.ok? ? nil : hallucination.flagged_claims,
        name_confidence: compute_name_confidence
      )
    end

    private

    def skip(reason)
      Result.new(subject: nil, body_html: nil, email_account: nil, thread_id: nil,
                 name_used: nil, intent: nil,
                 skip_reason: reason, prompt_used: @prompt_used, raw_response: @raw_response)
    end

    # True for intents that could resolve to a cold-touch outbound. :auto is
    # included because the Drafter picks the actual intent later; we want the
    # "too recent" guard to fire before the LLM call when there's a meaningful
    # chance the result will be a cold first touch.
    def cold_eligible_intent?(intent)
      %i[auto cold].include?(intent.to_sym)
    end

    # Classifies how confident we are in the first name used in the draft.
    # Persisted to Draft.name_confidence (enum: research_verified / email_prefix /
    # rescued_by_research).
    def compute_name_confidence
      # Unreliable name_source rescued by a verified research name.
      if @lead.name_source.in?(%w[email_prefix unknown]) && research_has_verified_name?
        return :rescued_by_research
      end

      # Research summary has a verified Name line — highest-confidence override.
      return :research_verified if research_has_verified_name?

      # Reliable manually-entered / enriched sources.
      return :research_verified if @lead.name_source.in?(%w[manual enriched])

      # Email-prefix guess or unknown — lowest confidence.
      :email_prefix
    end

    # True if the lead has a research summary with a verified identity (a
    # "- Name: <Real Name>" line that is NOT "Could not verify identity"). When
    # true the Drafter can proceed even if lead.first_name / name_source would
    # otherwise trip a guard. Memoized so repeat checks are cheap.
    def research_has_verified_name?
      return @research_has_verified_name if defined?(@research_has_verified_name)
      rs = context.dig(:research_summary)
      @research_has_verified_name = rs.present? &&
        rs.lines.any? { |l| l.strip.start_with?("- Name:") && !l.include?("Could not verify") }
    end

    # Memoized context (built once, reused by the name-confidence/research checks
    # and the main draft path).
    def context
      @context ||= Drafter::Context.new(@lead, intent: @intent).build
    end

    # Choose which EmailAccount drafts the email:
    # 1. Explicit param (caller's choice)
    # 2. Account that has prior thread history with this lead (most recent)
    # 3. Any active outreach account (first by created_at)
    def pick_email_account(ctx)
      return @explicit_email_account if @explicit_email_account

      prior_account_email = ctx[:thread_history]&.first&.dig(:account_email)
      if prior_account_email.present?
        account = EmailAccount.active.find_by("LOWER(email) = ?", prior_account_email.downcase)
        return account if account
      end

      EmailAccount.for_outreach.order(:created_at).first
    end

    def call_llm(prompt)
      Sendoff.config.llm_client.complete(prompt)
    end

    def parse_output(raw)
      json_str = raw.match(/```json\s*(\{.*?\})\s*```/m)&.captures&.first ||
                 raw.match(/\{[\s\S]*\}/)&.to_s ||
                 raw
      JSON.parse(json_str).transform_keys(&:to_sym)
    rescue JSON::ParserError => e
      raise Sendoff::LLMError, "Failed to parse LLM JSON output: #{e.message}\nraw: #{raw.first(300)}"
    end

    # Allowlist = persona.allowed_url_patterns + (if an account is present) a
    # pattern derived from the account's URL/subdomain.
    def validate_urls!(body_html, ctx)
      allowed = Array(Sendoff.config.persona.allowed_url_patterns).dup

      if (acct = ctx[:account])
        if acct.respond_to?(:account_url) && acct.account_url.present?
          allowed << %r{\A#{Regexp.escape(acct.account_url.to_s.sub(%r{/\z}, ""))}}
        elsif acct.respond_to?(:subdomain) && acct.subdomain.present?
          allowed << %r{\Ahttps?://#{Regexp.escape(acct.subdomain)}\.}
        end
      end

      body_html.to_s.scan(/https?:\/\/[^\s"<>]+/).each do |url|
        next if allowed.any? { |p| url.match?(p) }
        raise Sendoff::DisallowedUrlError, "LLM produced a disallowed URL: #{url}"
      end
    end

    def pick_thread_id(account, ctx, intent = @intent)
      return nil unless %i[reengage followup].include?(intent)

      match = ctx[:thread_history]&.find { |t| t[:account_email]&.downcase == account.email.downcase }
      match&.dig(:id)
    end
  end
end
