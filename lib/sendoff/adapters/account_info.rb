module Sendoff
  module Adapters
    # What an AccountLookup returns when a lead is recognized as an existing
    # account/customer in the host's system. All fields optional; the drafter
    # uses them to decide tone (cold prospect vs. existing customer), to allow
    # an account-specific URL, and to surface usage context in the prompt.
    AccountInfo = Struct.new(
      :subdomain,        # e.g. "acme" -> https://acme.example.com
      :account_url,
      :plan_name,
      :plan_label,       # human-friendly, e.g. "$49/mo Pro"
      :status,           # e.g. "active", "trialing", "canceled"
      :usage_label,      # short human summary of usage
      :looks_dormant,    # boolean
      :tenant_age_days,
      :metadata,         # free-form hash for host-specific extras
      keyword_init: true
    ) do
      def metadata = self[:metadata] || {}
    end
  end
end
