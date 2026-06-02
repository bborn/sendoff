module Sendoff
  # Central, mutable configuration. Sensible, network-free defaults so the
  # engine boots with zero setup; real hosts override via Sendoff.configure.
  class Configuration
    # Plug points
    attr_accessor :persona
    attr_accessor :llm_client
    attr_accessor :lead_source
    attr_accessor :account_lookup
    attr_accessor :brand_mention_source
    attr_accessor :gmail_client_factory

    # Behavior toggles / tunables
    attr_accessor :hallucination_critic_enabled
    attr_accessor :send_daily_cap
    attr_accessor :send_hourly_cap
    attr_accessor :recipient_cooldown_days
    attr_accessor :lead_fresh_touch_days

    # Recipient domains to exclude from Gmail thread/history lookups (e.g. your
    # own internal domains, so colleague threads don't pollute lead context).
    attr_accessor :excluded_recipient_domains

    def initialize
      @persona              = Persona.default
      @llm_client           = LLM::ClaudeCliClient.new
      @lead_source          = Adapters::NullLeadSource.new
      @account_lookup       = Adapters::NullAccountLookup.new
      @brand_mention_source = Adapters::NullBrandMentionSource.new

      # Lazily resolve the real Gmail client so this file has no app/ load-order
      # dependency. Hosts can replace with ->(account) { MyFakeGmail.new }.
      @gmail_client_factory = ->(email_account) {
        Sendoff::Gmail::Client.new(email_account)
      }

      @hallucination_critic_enabled = true
      @excluded_recipient_domains   = []
      @send_daily_cap          = Integer(ENV.fetch("SENDOFF_SEND_DAILY_CAP", 20))
      @send_hourly_cap         = Integer(ENV.fetch("SENDOFF_SEND_HOURLY_CAP", 5))
      @recipient_cooldown_days = Integer(ENV.fetch("SENDOFF_RECIPIENT_COOLDOWN_DAYS", 7))
      @lead_fresh_touch_days   = Integer(ENV.fetch("SENDOFF_LEAD_FRESH_TOUCH_DAYS", 4))
    end

    def gmail_client_for(email_account)
      @gmail_client_factory.call(email_account)
    end
  end
end
