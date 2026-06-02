module Sendoff
  class Drafter
    # Builds the full prompt sent to the LLM. Every piece of voice, product, and
    # sender identity comes from Sendoff.config.persona — there are no
    # host-specific strings here. Segment-specific guidance (e.g. a launch
    # discount for a particular vertical) comes from
    # persona.segment_prompt_hints[segment]; if absent, it is simply omitted.
    class Prompt
      # Generic free/consumer-mailbox domains we never cold-pitch.
      PERSONAL_EMAIL_DOMAINS = %w[
        gmail.com yahoo.com hotmail.com icloud.com outlook.com aol.com
        comcast.net me.com mac.com msn.com live.com ymail.com proton.me
        protonmail.com pm.me
      ].freeze

      # Use {SENDER_NAME} / {SENDER_DISPLAY_NAME} / {PRODUCT_NAME} as placeholders —
      # resolved in build().
      INTENT_INSTRUCTIONS = {
        cold: <<~TEXT,
          First-touch cold email. Lead has no prior conversation with the sender.

          ## Hard rules (these are non-negotiable)

          - **NEVER reference any internal signal that routed this lead to you** (a page view,
            a sign-up event, a download, etc.). The signal is internal routing only — this is
            how the lead was qualified, NOT something to mention. There are a million ways you
            could have found them. Read like legitimate cold outreach.

          - **No fake intimacy / fake-discovery language.** Do not write "I came across", "I stumbled upon",
            "I noticed someone from your team", or anything implying you've been watching them.

          - **Default to honest category credibility, NOT brand-specific specifics.** Structure:
            quick intro → category credibility sentence ("we work with a lot of companies in your space")
            → open question → sign off.

          - **Brand-specific details require earned framing** ("spent some time on your site and
            noticed…"). When in doubt, skip. Generic > forced-specific. If this email could be sent to
            a hundred similar companies, that is FINE — that's what good cold outreach looks like.

          - **No external articles / trend links as filler.** Default: no link.

          - **Close with an open, low-pressure question** inviting a reply.

          - **No calendar URL on first touch.**

          - **60-120 words total. No em-dashes anywhere.**
        TEXT

        reengage: <<~TEXT,
          Second-touch re-engagement email. The sender had a prior thread with this lead that went quiet.
          Now there's a new signal and we're reaching back out — but the SIGNAL ITSELF is internal-only.

          ## Hard rules

          - **You MUST pick a DIFFERENT angle than the first email.** Read the prior_thread_history block
            carefully. Whatever angle, opener, or hook it used, do NOT repeat it.

          - **You MAY briefly acknowledge the prior outreach.** Examples:
            - "Quick follow-up to the note from a few weeks back."
            - "Wanted to circle back with a different thought." (avoid the literal phrase "circle back" — rephrase.)
            - "Quick second note in case the first one got buried."
            Or skip the meta-acknowledgement entirely and lead with the new angle.

          - **You MUST pick a different angle from these:**
            - A specific product feature/case study relevant to their vertical
              (e.g. "we just rolled out X — thought of you because Y")
            - A genuine observation about a specific recent piece of their public content,
              framed naturally ("spent some time on your site and noticed…")
            - A pointed question about a specific problem in their workflow
            - A short, useful observation about the category that's actionable for them

          - **NEVER mention any internal routing signal or re-engagement context.**
            The signal is internal routing only.

          - **Same voice rules apply:** 60-120 words, {SENDER_NAME}'s voice, no em dashes, no fake-discovery language.

          - **Calendar URL OK** as a soft option ("if a 15-minute call would help, here's my calendar").

          - This is a REPLY to the prior thread (use the same thread_id). The subject line should be the
            prior thread's subject WITHOUT the "Re: " prefix — the mailer adds it.
        TEXT

        checkin: <<~TEXT,
          Customer-success check-in. Lead has an active account with {PRODUCT_NAME}.
          This is a relationship/support email, not a sales pitch.

          ## Hard rules

          - **Address them as a customer, not a prospect.** They already use the product.
            Do NOT pitch {PRODUCT_NAME}. Do NOT introduce the product.

          - **Reference their account by URL** when one is available in the context.
            That signals you actually know they're a customer.

          - **3-5 specific recent product updates** relevant to their segment. Concrete, not marketing-speak.
            If you don't know specific updates, ask them what they'd find useful instead — DO NOT fabricate.

          - **Offer a walk-through** via your calendar if a calendar URL is permitted.

          - **Same voice rules:** Direct. Generous. Understated. No em dashes, no buzzwords.

          - **Sign off as the sender** (name already provided at the top of this prompt — match it exactly).

          - **80-150 words** (slightly longer than cold because of feature list).
        TEXT

        followup: <<~TEXT
          Light follow-up on a recent thread that didn't get a reply. Very short.

          ## Hard rules

          - **Reference the prior thread** subtly — the recipient saw the first email, you don't need to
            re-explain. One short paragraph.

          - **No pitch, no features list.** This is a nudge, not a re-sell.

          - **One question OR one specific ask.** Examples:
            - "Did this land? Happy to take it off your radar if not the right time."
            - "Still useful to chat?"
            - "Worth a 10-minute call?"

          - **Match the prior thread's tone exactly.** Read prior_thread_history.

          - **30-60 words. Sign off short — usually just "Thanks, {SENDER_NAME}" with no title.**

          - **Same hard rules:** no em dashes, no fake-discovery language, no internal-signal references.

          - This is a REPLY to the prior thread (use same thread_id). Subject is prior subject without "Re: ".
        TEXT
      }.freeze

      def initialize(ctx, email_account:)
        @ctx = ctx
        @email_account = email_account
        @persona = Sendoff.config.persona
      end

      # Returns the full prompt sent to the LLM. Stored verbatim on the Draft
      # record so the operator can inspect what the agent actually saw.
      def build
        sender_name = @email_account.first_name.presence || @email_account.display_name
        product = @persona.product_name

        <<~PROMPT
          You draft outreach emails for #{product}#{product_description_clause}.
          Your output must be indistinguishable from something #{@email_account.display_name} would write themselves.

          You are writing as: #{@email_account.display_name} <#{@email_account.email}>
          Sign off as: #{sender_name}

          ## Voice guide (the gold standard for tone)

          #{@persona.voice_guide}

          ## Outreach principles

          #{@persona.outreach_principles}

          ## Context for this draft

          #{format_context}

          #{intent_section(sender_name)}

          ## Voice rules (project-specific, override anything above if they conflict)

          #{build_voice_rules_section}

          ## URLs you may use

          #{allowed_urls_section}

          ## Output format — JSON only, no preamble

          ```json
          {
          #{"  \"intent\": \"cold|reengage|checkin|followup\"," if @ctx[:intent] == :auto}
            "subject": "...",
            "body_html": "...",
            "name_used": "First name you actually addressed them as",
            "skip_reason": null
          }
          ```

          If you cannot write a quality draft (e.g. context too thin, can't verify they're a real lead,
          personal email domain, etc.), return:
          ```json
          { "skip_reason": "<short reason>" }
          ```

          For reengage/followup intent, write as a reply (subject without "Re:" — mailer adds it).
          For cold intent the subject should be fresh — never "Re:".

          Return the JSON object now, no preamble.
        PROMPT
      end

      private

      def product_description_clause
        desc = @persona.product_description.to_s.strip
        desc.present? ? " (#{desc})" : ""
      end

      def intent_section(sender_name)
        if @ctx[:intent] == :auto
          build_auto_intent_section(sender_name)
        else
          explicit = INTENT_INSTRUCTIONS[@ctx[:intent]] || INTENT_INSTRUCTIONS[:cold]
          instructions = resolve_placeholders(explicit, sender_name)
          parts = [ "## Intent: #{@ctx[:intent]}", "", instructions ]
          hint = segment_hint
          parts << "" << hint if hint && show_segment_hint?(@ctx[:intent])
          parts.join("\n")
        end
      end

      def build_auto_intent_section(sender_name)
        sections = []
        sections << "## Intent — you must pick the best one"
        sections << ""
        sections << <<~GUIDE.strip
          Based on all signals below, choose ONE of the four intents. Decision guide:
          - **checkin**: They have an active account (`account` present) → prefer checkin.
          - **followup**: `thread_history` (with THIS exact email) has at least one prior thread AND days_since_last_contact < 30 → follow-up nudge.
          - **reengage**: `thread_history` (with THIS exact email) has at least one prior thread AND days_since_last_contact ≥ 30 → re-engage with new angle.
          - **cold**: No `thread_history` with this exact lead AND no account → cold introduction.

          ## CRITICAL — reengage vs cold

          `domain_thread_history` (prior threads with DIFFERENT people at the same domain) is NOT enough
          to pick reengage or followup. Reengage REQUIRES a prior thread with the lead's exact email.

          NEVER write phrases like "following up on my note from last year" or "my previous email"
          UNLESS `thread_history` has an actual thread with this exact lead's email address.
          Fabricating prior contact is a hard rule violation.

          If `domain_thread_history` has activity but `thread_history` is empty:
            → Intent is COLD (no prior conversation with this person).
            → You MAY soften the cold tone with a light, accurate reference: "we have been in touch
              with some folks at your team in the past" — but only if it adds value.
            → NEVER imply you have personally emailed THIS person before.

          When signals conflict: account (checkin) > thread_history < 30d (followup) > thread_history ≥ 30d (reengage) > otherwise (cold).

          Return your chosen intent in the "intent" field of the JSON output.
        GUIDE
        sections << ""

        INTENT_INSTRUCTIONS.each do |intent_key, text|
          resolved = resolve_placeholders(text, sender_name)
          sections << "---"
          sections << "### If intent = #{intent_key}"
          sections << ""
          sections << resolved
          if (hint = segment_hint) && show_segment_hint?(intent_key)
            sections << ""
            sections << hint
          end
          sections << ""
        end

        sections.join("\n")
      end

      BRAND_MENTION_VOICE_RULE = <<~RULE.strip
        - You may only reference "people in our network posting about <brand>" or "people talking about <brand>" if brand_mentions_count (shown in context) is greater than 0. If brand_mentions_count is 0 or absent, do not make this claim.
      RULE

      def build_voice_rules_section
        parts = []
        parts << @ctx[:voice_rules].presence
        parts << BRAND_MENTION_VOICE_RULE
        parts.compact.join("\n")
      end

      def resolve_placeholders(text, sender_name)
        text
          .gsub("{SENDER_NAME}", sender_name)
          .gsub("{SENDER_DISPLAY_NAME}", @email_account.display_name)
          .gsub("{PRODUCT_NAME}", @persona.product_name.to_s)
      end

      # The host-supplied, segment-specific guidance block (e.g. a vertical-specific
      # offer). nil when there is no hint for this segment.
      def segment_hint
        return @segment_hint if defined?(@segment_hint)
        seg = @ctx.dig(:company, :segment).to_s
        hints = @persona.segment_prompt_hints || {}
        @segment_hint = hints[seg] || hints[seg.to_sym]
        @segment_hint = @segment_hint.to_s.strip.presence
      end

      # Segment hints only apply to first-touch and check-in intents — continuation
      # threads (reengage/followup) should not have an inserted pitch.
      def show_segment_hint?(intent)
        %i[cold checkin].include?(intent.to_sym)
      end

      def allowed_urls_section
        lines = [ "Only the following URLs are allowed in the body. Anything else raises an error:" ]
        @persona.allowed_url_patterns.each do |pattern|
          lines << "- #{describe_pattern(pattern)}"
        end
        if (acct = @ctx[:account]) && acct.respond_to?(:account_url) && acct.account_url.present?
          lines << "- #{acct.account_url}  (their account — checkin only)"
        elsif (acct = @ctx[:account]) && acct.respond_to?(:subdomain) && acct.subdomain.present?
          lines << "- their account subdomain: #{acct.subdomain}  (checkin only)"
        end
        lines << "- (none configured)" if @persona.allowed_url_patterns.empty? && @ctx[:account].blank?
        lines.join("\n")
      end

      # Best-effort human description of a Regexp allowlist entry.
      def describe_pattern(pattern)
        src = pattern.is_a?(Regexp) ? pattern.source : pattern.to_s
        src.gsub('\A', "").gsub('\/', "/").gsub('\.', ".").gsub('\\', "")
      end

      def format_context
        lead         = @ctx[:lead]
        comp         = @ctx[:company]
        acct         = @ctx[:account]
        threads      = @ctx[:thread_history] || []
        dom_threads  = @ctx[:domain_thread_history] || []
        notes        = @ctx[:company_notes] || []
        voice_exs    = @ctx[:voice_examples] || []
        research     = @ctx[:research_summary]

        lines = []

        if research.present?
          lines += [
            "<research_summary>",
            "  IMPORTANT: This is pre-researched intel about this lead. Use the REAL first name from",
            "  the 'Name:' line below, not the email_prefix-derived name. If research says the person",
            "  has left the company or is otherwise unsuitable, return skip_reason: enrichment_indicates_skip.",
            ""
          ]
          research.to_s.each_line { |l| lines << "  #{l.rstrip}" }
          lines << "</research_summary>"
        end

        lines += [
          "<intent>#{@ctx[:intent]}</intent>",
          "<lead>",
          "  email: #{lead[:email]}",
          "  first_name: #{lead[:first_name].presence || '(unknown)'}",
          "  full_name: #{lead[:full_name].presence || '(unknown)'}",
          "  name_source: #{lead[:name_source]}  # 'manual'/'enriched' are reliable; 'email_prefix' means we don't really know",
          "</lead>",
          "<company>",
          "  name: #{comp[:name]}",
          "  domain: #{comp[:domain]}",
          "  segment: #{comp[:segment]}",
          "</company>",
          "<brand_mentions_count>#{@ctx[:brand_mentions_count].to_i}</brand_mentions_count>"
        ]

        if acct
          lines += [
            "<account>",
            "  plan_name: #{acct.plan_name.inspect}",
            "  plan_label: #{acct.plan_label.inspect}",
            "  status: #{acct.status}",
            "  subdomain: #{acct.subdomain}",
            "  account_url: #{acct.account_url}",
            "  tenant_age_days: #{acct.tenant_age_days}",
            "  looks_dormant: #{acct.looks_dormant}",
            "  usage_summary: #{acct.usage_label.inspect}",
            "</account>",
            "",
            "<account_usage_guidance>",
            "  IF looks_dormant is true: do NOT write as if they're an active customer.",
            "  Their account was likely auto-provisioned. Frame as 'noticed you signed up but it",
            "  doesn't look like you've had a chance to set things up yet — happy to walk you through it'.",
            "  Genuine + low pressure. NEVER say 'make sure it's working for your team' when there is",
            "  no team in the account.",
            "</account_usage_guidance>"
          ]
        else
          lines << "<account>none — this lead has no account</account>"
        end

        intent_signals = build_intent_signals
        if intent_signals.present?
          lines << "<signals_for_intent_only>"
          lines << "  NOTE: These signals inform which intent to pick. NEVER mention them in the email body."
          lines << intent_signals
          lines << "</signals_for_intent_only>"
        end

        if threads.any?
          lines << "<prior_thread_history>  # grouped by sending account, exact lead match"
          threads.first(5).each do |t|
            lines << "  - from=#{t[:account_name]} <#{t[:account_email]}> subject=#{t[:subject].inspect} last=#{t[:last_date]} messages=#{t[:messages]}"
          end
          lines << "</prior_thread_history>"
        end

        if dom_threads.any?
          lines << "<domain_thread_history>  # threads with OTHER contacts at #{comp[:domain]} — not this exact lead"
          lines << "  NOTE: If no prior thread with this lead but domain threads exist, you MAY reference the"
          lines << "  existing relationship lightly (e.g. 'we have been in touch with [name] in the past') —"
          lines << "  ONLY if it adds value. When in doubt, go fresh."
          dom_threads.first(5).each do |t|
            lines << "  - contact=#{t[:from]} via=#{t[:account_name]} <#{t[:account_email]}> subject=#{t[:subject].inspect} last=#{t[:last_date]}"
          end
          lines << "</domain_thread_history>"
        end

        if notes.any?
          lines << "<company_notes>  # internal research notes — may contain real contact name + role"
          notes.first(3).each do |n|
            lines << "  - [#{n[:created_at].to_s.first(10)}] #{n[:title]}: #{n[:content].first(500)}"
          end
          lines << "</company_notes>"
        end

        if voice_exs.any?
          lines << "<voice_examples>"
          lines << "  NOTE: These are recent successful sends by the same sender. Match their voice exactly."
          lines << "  They are the source of truth for tone — override the static voice guide if they conflict."
          voice_exs.each_with_index do |ex, i|
            body_text = ex[:body_html].to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip.first(400)
            lines << "  [#{i + 1}] Subject: #{ex[:subject]}"
            lines << "       Body excerpt: #{body_text}"
          end
          lines << "</voice_examples>"
        end

        lines.join("\n")
      end

      def build_intent_signals
        parts = []

        reports = @ctx[:reports_viewed] || []
        if reports.any?
          rv = reports.first
          date_str = rv[:viewed_at] ? " (last: #{rv[:viewed_at].to_date})" : ""
          parts << "  reports_viewed: #{rv[:count]}#{date_str}"
        else
          parts << "  reports_viewed: 0"
        end

        if @ctx[:days_since_last_contact]
          parts << "  days_since_last_contact: #{@ctx[:days_since_last_contact]}"
        else
          parts << "  days_since_last_contact: none (no prior thread)"
        end

        acct = @ctx[:account]
        if acct
          parts << "  account: active (#{acct.subdomain})"
        else
          parts << "  account: none"
        end

        seg = @ctx.dig(:company, :segment).presence || "unknown"
        parts << "  company_segment: #{seg}"

        parts.join("\n")
      end
    end
  end
end
