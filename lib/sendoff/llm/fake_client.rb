require "json"

module Sendoff
  module LLM
    # A deterministic, network-free LLM client for tests and the demo. It never
    # calls an API, so the engine's whole drafting pipeline runs green with no
    # secrets.
    #
    # Three modes, in priority order:
    #   1. A handler proc:   FakeClient.new { |prompt| "..." }
    #   2. A scripted queue: FakeClient.new(responses: ["...", "..."])  # shifted per call
    #   3. Default:          returns a generic, valid draft JSON (see #default_for)
    #
    # The default inspects the prompt for light cues so the drafter, voice
    # critic, and hallucination critic each get a parseable response.
    class FakeClient
      attr_reader :prompts

      def initialize(responses: nil, &handler)
        @handler   = handler
        @responses = responses ? responses.dup : nil
        @prompts   = []
      end

      def complete(prompt)
        @prompts << prompt
        return @handler.call(prompt) if @handler
        return @responses.shift     if @responses && !@responses.empty?

        default_for(prompt)
      end

      private

      def default_for(prompt)
        p = prompt.to_s.downcase
        if p.include?("hallucination") || p.include?("fact-check") || p.include?("flagged_claims")
          { ok: true, flagged_claims: [], reason: nil }.to_json
        elsif p.include?("copy editor") || p.include?("voice critic") || p.include?("rewrite")
          { subject: "Quick question", body_html: "<p>Hi there — quick question for you.</p>" }.to_json
        else
          {
            subject: "Quick question",
            body_html: "<p>Hi there,</p><p>Saw your work and wanted to reach out.</p>",
            intent: "cold",
            name_used: "there",
            skip_reason: nil
          }.to_json
        end
      end
    end
  end
end
