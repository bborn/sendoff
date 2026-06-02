module Sendoff
  module Adapters
    # A LeadSource is where warm leads come from. The engine's sync job calls
    # #fetch and upserts whatever it returns. In the original host app this was
    # a query against the host’s production DB for recent signups; in the OSS
    # engine it's an adapter you implement (or the bundled Example one).
    #
    # Implement #fetch to return an Array<Sendoff::Adapters::LeadData>.
    class LeadSource
      def fetch
        raise Sendoff::NotImplementedError, "#{self.class}#fetch must return Array<LeadData>"
      end
    end

    # Default: no external leads. Keeps the engine bootable with zero config.
    class NullLeadSource < LeadSource
      def fetch = []
    end
  end
end
