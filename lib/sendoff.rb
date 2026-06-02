require "sendoff/version"
require "sendoff/engine"

# Pure-Ruby framework layer (not Zeitwerk-autoloaded; required explicitly).
require "sendoff/errors"
require "sendoff/persona"
require "sendoff/adapters/lead_data"
require "sendoff/adapters/account_info"
require "sendoff/adapters/lead_source"
require "sendoff/adapters/account_lookup"
require "sendoff/adapters/brand_mention_source"
require "sendoff/llm/claude_cli_client"
require "sendoff/llm/fake_client"
require "sendoff/configuration"

# Bundled, fully-fictional example adapter (demo + tests; no network/secrets).
require "sendoff/adapters/example/lead_source"

# Sendoff is the generic, open-source core of an SDR outreach tool.
#
# Domain-specific behavior plugs in through three adapters (lead source,
# account lookup, brand-mention source), a persona (who is writing, in what
# voice, to sell what), and a pluggable LLM client. Everything else — the
# pipeline state machine, the drafter + critics, send-safety, Gmail, MCP — is
# generic and ships in the box.
#
#   Sendoff.configure do |c|
#     c.persona      = Sendoff::Persona.new(product_name: "Acme", sender_name: "Dana", ...)
#     c.lead_source  = MyCrm::LeadSource.new
#     c.llm_client   = Sendoff::LLM::ClaudeCliClient.new
#   end
module Sendoff
  class << self
    def configuration
      @configuration ||= Configuration.new
    end
    alias config configuration

    def configure
      yield(configuration)
      configuration
    end

    # Reset to defaults — primarily a test hook.
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
