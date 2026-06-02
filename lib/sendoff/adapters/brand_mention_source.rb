module Sendoff
  module Adapters
    # Optional "social proof" data. In the original host app this counted how many
    # creators in the network had recently posted about a company's competitors
    # (used to justify a claim in the email). Generic hosts can return 0 / [].
    #
    # Implement:
    #   #count_for(company)       -> Integer   (recent brand mentions)
    #   #competitors_for(company) -> Array     (competitor descriptors)
    class BrandMentionSource
      def count_for(_company)       = 0
      def competitors_for(_company) = []
    end

    # Default: no brand-mention data available.
    class NullBrandMentionSource < BrandMentionSource; end
  end
end
