module Sendoff
  module Adapters
    module Example
      # A fully fictional, in-memory LeadSource for the demo + tests. No network,
      # no secrets, no real people or companies. Wire it up with:
      #
      #   Sendoff.config.lead_source = Sendoff::Adapters::Example::LeadSource.new
      #
      # #fetch returns a varied set of LeadData spanning several segments
      # (agency / brand / nonprofit) with realistic warmth `signals`, plus a
      # couple of personal free-email addresses so the engine's skiplist is
      # exercised.
      class LeadSource < Sendoff::Adapters::LeadSource
        def fetch
          self.class.leads
        end

        # The fictional seed set. Kept as a class method so specs can assert on
        # it directly and so the demo task can introspect it.
        def self.leads
          [
            # --- Agency (classified via domain keywords: media / marketing / studio) ---
            LeadData.new(
              email: "hello@brightwavemedia.com",
              full_name: "Dana Okafor",
              company_name: "Brightwave Media",
              company_domain: "brightwavemedia.com",
              signals: { reports_viewed: 5, total_views: 22, last_viewed_at: days_ago(2) }
            ),
            LeadData.new(
              email: "team@northstar-marketing.com",
              company_name: "Northstar Marketing",
              company_domain: "northstar-marketing.com",
              signals: { reports_viewed: 2, total_views: 4, last_viewed_at: days_ago(20) }
            ),
            LeadData.new(
              email: "reps@pinehurststudio.com",
              full_name: "Sasha Lindqvist",
              company_name: "Pinehurst Studio",
              company_domain: "pinehurststudio.com",
              signals: { reports_viewed: 4, total_views: 18, last_viewed_at: days_ago(3) }
            ),

            # --- Nonprofit (classified via .org TLD / "alliance" / "foundation") ---
            LeadData.new(
              email: "marketing@riverkeepalliance.org",
              full_name: "Priya Anand",
              first_name: "Priya",
              last_name: "Anand",
              company_name: "Riverkeep Alliance",
              company_domain: "riverkeepalliance.org",
              signals: { reports_viewed: 6, total_views: 41, last_viewed_at: days_ago(1) }
            ),
            LeadData.new(
              # Explicit segment hint from the source — exercises the
              # "honor the source's segment, skip auto-classify" path in Leads::Sync.
              email: "outreach@cedarvalefoundation.org",
              first_name: "Owen",
              last_name: "Brûlé",
              company_name: "Cedarvale Foundation",
              company_domain: "cedarvalefoundation.org",
              segment: :nonprofit,
              signals: { reports_viewed: 3, total_views: 12, last_viewed_at: days_ago(6) }
            ),

            # --- Brand (fallback segment: no agency/nonprofit signal) ---
            LeadData.new(
              email: "growth@fernwoodgoods.com",
              full_name: "Marcus Bell",
              company_name: "Fernwood Goods",
              company_domain: "fernwoodgoods.com",
              signals: { reports_viewed: 1, total_views: 2, last_viewed_at: days_ago(45) }
            ),
            LeadData.new(
              email: "partnerships@harborlinecoffee.com",
              full_name: "Nadia Roy",
              company_name: "Harborline Coffee",
              company_domain: "harborlinecoffee.com",
              signals: { reports_viewed: 7, total_views: 55, last_viewed_at: days_ago(0) }
            ),
            LeadData.new(
              # Second lead at an existing domain — exercises company reuse and
              # the "keep the warmest lead's pipeline entry" path. Lower signals.
              email: "ops@harborlinecoffee.com",
              full_name: "Theo Park",
              company_name: "Harborline Coffee",
              company_domain: "harborlinecoffee.com",
              signals: { reports_viewed: 2, total_views: 6, last_viewed_at: days_ago(9) }
            ),

            # --- email-prefix name derivation (no name fields supplied) ---
            LeadData.new(
              email: "casey.morgan@willowpeakapps.com",
              company_name: "Willowpeak Apps",
              company_domain: "willowpeakapps.com",
              signals: { reports_viewed: 3, total_views: 9, last_viewed_at: days_ago(4) }
            ),

            # --- Personal / free-email addresses: MUST be skipped ---
            LeadData.new(
              email: "jess.personal@gmail.com",
              full_name: "Jess Personal",
              signals: { reports_viewed: 9, total_views: 99, last_viewed_at: days_ago(0) }
            ),
            LeadData.new(
              email: "sidehustle@yahoo.com",
              signals: { reports_viewed: 4, total_views: 14, last_viewed_at: days_ago(1) }
            )
          ]
        end

        def self.days_ago(n)
          (Date.today - n).to_s
        end
      end
    end
  end
end
