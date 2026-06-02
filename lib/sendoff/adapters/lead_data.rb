module Sendoff
  module Adapters
    # The normalized shape a LeadSource yields. The engine maps these into its
    # own Lead / Company / PipelineEntry records. `signals` is a free-form hash
    # of warmth indicators (e.g. reports_viewed, total_views, last_viewed_at)
    # that feed warm-score computation; nothing in the engine requires any
    # particular key.
    LeadData = Struct.new(
      :email,
      :full_name,
      :first_name,
      :last_name,
      :company_name,
      :company_domain,
      :segment,
      :signals,
      keyword_init: true
    ) do
      def signals = self[:signals] || {}
    end
  end
end
