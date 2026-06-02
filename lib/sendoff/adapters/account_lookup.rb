module Sendoff
  module Adapters
    # Given a Lead, decide whether they map to a known account/customer in the
    # host system and return an AccountInfo (or nil for "unknown / cold").
    # In a typical host this walks user -> account -> subscription.
    #
    # Implement #find(lead) -> Sendoff::Adapters::AccountInfo | nil.
    class AccountLookup
      def find(_lead)
        raise Sendoff::NotImplementedError, "#{self.class}#find(lead) must return AccountInfo or nil"
      end
    end

    # Default: every lead is treated as a cold prospect (no account).
    class NullAccountLookup < AccountLookup
      def find(_lead) = nil
    end
  end
end
