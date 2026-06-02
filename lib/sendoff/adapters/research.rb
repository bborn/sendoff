module Sendoff
  module Adapters
    # A Research adapter turns a Lead into a markdown research summary that the
    # enrichment pipeline saves as a Note (and uses to reclassify the company's
    # segment). It is intentionally dependency-light: the only collaborator is
    # the engine's pluggable LLM client (Sendoff.config.llm_client). No web
    # scraping SDKs, no MCP servers, no host databases.
    #
    # Implement #research(lead) to return a String markdown summary, or nil to
    # signal "no research available" (the enrichment job then no-ops).
    #
    #   Sendoff.configure { |c| c.research_adapter = Sendoff::Adapters::LLMResearch.new }
    class Research
      # @param lead [Sendoff::Lead]
      # @return [String, nil] a markdown research summary, or nil for no-op.
      def research(_lead)
        raise Sendoff::NotImplementedError, "#{self.class}#research(lead) must return a markdown String or nil"
      end
    end

    # Default: enrichment is a no-op. Keeps the engine bootable and the lead
    # sync harmless with zero configuration — research always returns nil.
    class NullResearch < Research
      def research(_lead) = nil
    end

    # Generic LLM-backed research. Builds a host-agnostic prompt asking the model
    # to (1) find the real person + role from public sources, (2) categorize the
    # company into the engine's generic segments, (3) summarize recent activity,
    # and (4) flag red flags — then returns the cleaned text.
    #
    # The prompt is deliberately free of any host product, scraping tool, or
    # database references. It only knows the engine's generic segment taxonomy.
    #
    # CONTRACT: the output MUST contain a line formatted exactly
    #   - Name: <real name>
    # (or a "Could not verify identity" line) inside a "=== Research Summary ==="
    # block, because Sendoff::Drafter::Context scans for "- Name:" lines to
    # rescue weak names. The prompt enforces this format.
    class LLMResearch < Research
      # Generic segment buckets the classifier understands. Sourced from the
      # SegmentClassifier so the prompt and the classifier never drift apart.
      SEGMENTS = %w[agency brand nonprofit unknown].freeze

      def research(lead)
        prompt = build_prompt(lead)
        raw    = Sendoff.config.llm_client.complete(prompt)
        clean(raw)
      end

      private

      def build_prompt(lead)
        company = lead.company
        <<~PROMPT
          You are a B2B sales research assistant. Research the lead below using
          public, openly-available information and output a single structured
          markdown summary. Do not invent facts; if you cannot verify something,
          say so plainly.

          ## Lead to research

          - Email: #{lead.email}
          - Name on file: #{lead.full_name.presence || '(unknown — derived from the email prefix only)'}
          - Name source: #{lead.name_source} (email_prefix = guessed from the email local-part; enriched/manual = previously verified)
          - Company: #{company&.name} (#{company&.domain})
          - Company segment on file: #{company&.segment.presence || 'unknown'}

          ## What to find

          1. The real person + role
             - The email prefix may be only a surname, initials, or a role
               address (e.g. info@, hello@, marketing@). Identify the real
               first + last name of a plausible decision-maker from public
               sources (the company's own About/Team/Leadership page, public
               professional profiles, press mentions).
             - If the address is clearly a shared/role inbox, look for a
               decision-maker at the company instead.

          2. Company category
             - Categorize the company into exactly one of these generic
               segments: #{SEGMENTS.join(', ')}.
               * agency    — markets / runs campaigns on behalf of clients
               * brand     — sells its own product or service directly
               * nonprofit — charity, foundation, association, or similar
               * unknown   — not enough signal to decide
             - Put your choice on the "- Category:" line below.

          3. Recent activity (roughly the last 60 days)
             - Any public news, press, hiring, product, or social activity.
               If nothing is found, write "none found".

          4. Red flags
             - Anything that would make outreach a poor fit: the person appears
               to have left, the address is a generic role inbox, the
               organization is an implausible prospect, etc. If none, write "none".

          ## Output format

          Output EXACTLY this block (plain text, no commentary before or after):

          === Research Summary ===
          - Name: <real first + last name>
          - Title: <role, or "unknown">
          - Found via: <sources used>
          - Category: <#{SEGMENTS.join(' / ')}>
          - Company details: <2-3 facts: size, market, recent moves>
          - Recent activity: <news/hires/posts in the last 60 days, or "none found">
          - Notes / flags: <red flags or special considerations, or "none">

          If you cannot verify the real person's name from a public source,
          output THIS block instead (keep the same header):

          === Research Summary ===
          - Could not verify identity beyond the email prefix
          - Skip recommendation: confidence too low for personalization

          Do not add any preamble, explanation, or text outside the
          === Research Summary === block.
        PROMPT
      end

      # Strip ANSI escapes (some CLI clients emit them) and surrounding
      # whitespace; return nil for an empty result so the job can no-op.
      def clean(raw)
        text = raw.to_s.gsub(/\x1b\[[0-9;]*[mGKHFJA-Za-z]/, "").strip
        text.presence
      end
    end
  end
end
