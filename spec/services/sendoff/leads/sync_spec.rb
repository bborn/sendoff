require "rails_helper"

RSpec.describe Sendoff::Leads::Sync do
  # A tiny in-memory lead source for controlled assertions.
  class StubLeadSource < Sendoff::Adapters::LeadSource
    def initialize(leads) = (@leads = leads)
    def fetch = @leads
  end

  def ld(**attrs)
    Sendoff::Adapters::LeadData.new(**attrs)
  end

  def use_source(leads)
    Sendoff.config.lead_source = StubLeadSource.new(leads)
  end

  describe "with the bundled Example::LeadSource" do
    before { Sendoff.config.lead_source = Sendoff::Adapters::Example::LeadSource.new }

    it "creates companies, leads, and pipeline entries" do
      described_class.call

      expect(Sendoff::Company.count).to be > 0
      expect(Sendoff::Lead.count).to be > 0
      expect(Sendoff::PipelineEntry.count).to eq(Sendoff::Lead.count)
    end

    it "skips personal/free-email addresses" do
      described_class.call

      expect(Sendoff::Lead.where("email LIKE ?", "%@gmail.com").count).to eq(0)
      expect(Sendoff::Lead.where("email LIKE ?", "%@yahoo.com").count).to eq(0)
    end

    it "reports skipped counts for the personal addresses" do
      stats = described_class.call
      expect(stats[:skipped]).to be >= 2
      expect(stats[:errors]).to eq(0)
    end

    it "classifies segments (agency / brand / nonprofit all present)" do
      described_class.call
      segments = Sendoff::Company.distinct.pluck(:segment)
      expect(segments).to include("agency", "brand", "nonprofit")
    end

    it "starts every new pipeline entry at the :new stage" do
      described_class.call
      expect(Sendoff::PipelineEntry.distinct.pluck(:stage)).to eq([ "new" ])
    end

    it "is idempotent: re-running creates no duplicates" do
      described_class.call
      companies = Sendoff::Company.count
      leads     = Sendoff::Lead.count
      entries   = Sendoff::PipelineEntry.count

      stats = described_class.call

      expect(Sendoff::Company.count).to eq(companies)
      expect(Sendoff::Lead.count).to eq(leads)
      expect(Sendoff::PipelineEntry.count).to eq(entries)
      expect(stats[:created]).to eq(0)
      expect(stats[:updated]).to be > 0
    end

    it "reuses one company for multiple leads on the same domain" do
      described_class.call
      harbor = Sendoff::Company.find_by(domain: "harborlinecoffee.com")
      expect(harbor).to be_present
      expect(harbor.leads.count).to eq(2)
    end
  end

  describe "name derivation" do
    it "uses provided name fields with name_source=enriched" do
      use_source([ ld(email: "dana@brightwavemedia.com", full_name: "Dana Okafor",
                       company_name: "Brightwave", company_domain: "brightwavemedia.com") ])
      described_class.call

      lead = Sendoff::Lead.find_by(email: "dana@brightwavemedia.com")
      expect(lead.full_name).to eq("Dana Okafor")
      expect(lead.first_name).to eq("Dana")
      expect(lead.last_name).to eq("Okafor")
      expect(lead.name_source).to eq("enriched")
    end

    it "falls back to email local-part with name_source=email_prefix" do
      use_source([ ld(email: "casey.morgan@willowpeakapps.com",
                      company_name: "Willowpeak", company_domain: "willowpeakapps.com") ])
      described_class.call

      lead = Sendoff::Lead.find_by(email: "casey.morgan@willowpeakapps.com")
      expect(lead.full_name).to eq("Casey Morgan")
      expect(lead.first_name).to eq("Casey")
      expect(lead.last_name).to eq("Morgan")
      expect(lead.name_source).to eq("email_prefix")
    end
  end

  describe "warm_score computation" do
    it "scores heavy + recent engagement highly" do
      use_source([ ld(email: "hot@acme.co", company_name: "Acme", company_domain: "acme.co",
                      signals: { reports_viewed: 6, total_views: 40, last_viewed_at: Date.today.to_s }) ])
      described_class.call

      pe = Sendoff::Lead.find_by(email: "hot@acme.co").pipeline_entries.first
      # +3 (>=3) +2 (>=5) +1 (views>=10) +2 (<=7d) +1 (<=2d) = 9 capped reasoning -> 9
      expect(pe.warm_score).to eq(9)
      expect(pe.reports_viewed).to eq(6)
      expect(pe.signals["reports_viewed"]).to eq(6)
    end

    it "scores cold, stale engagement at zero" do
      use_source([ ld(email: "cold@acme.co", company_name: "Acme", company_domain: "acme.co",
                      signals: { reports_viewed: 1, total_views: 2, last_viewed_at: (Date.today - 90).to_s }) ])
      described_class.call

      pe = Sendoff::Lead.find_by(email: "cold@acme.co").pipeline_entries.first
      expect(pe.warm_score).to eq(0)
    end

    it "stores warmth indicators in the signals jsonb" do
      use_source([ ld(email: "x@acme.co", company_name: "Acme", company_domain: "acme.co",
                      signals: { reports_viewed: 3, total_views: 11, last_viewed_at: Date.today.to_s }) ])
      described_class.call

      pe = Sendoff::Lead.find_by(email: "x@acme.co").pipeline_entries.first
      expect(pe.signals).to include("reports_viewed" => 3, "total_views" => 11)
      expect(pe.warm_signal?).to be(true)
    end

    it "refreshes signals (but not stage) on re-run" do
      use_source([ ld(email: "y@acme.co", company_name: "Acme", company_domain: "acme.co",
                      signals: { reports_viewed: 1, total_views: 1, last_viewed_at: (Date.today - 30).to_s }) ])
      described_class.call
      pe = Sendoff::Lead.find_by(email: "y@acme.co").pipeline_entries.first
      pe.update!(stage: "contacted")

      use_source([ ld(email: "y@acme.co", company_name: "Acme", company_domain: "acme.co",
                      signals: { reports_viewed: 7, total_views: 50, last_viewed_at: Date.today.to_s }) ])
      described_class.call

      pe.reload
      expect(pe.stage).to eq("contacted") # unchanged
      expect(pe.warm_score).to be > 0
      expect(pe.reports_viewed).to eq(7)
    end
  end

  describe "segment hints" do
    it "honors an explicit segment from the lead source" do
      use_source([ ld(email: "reps@lume.co", company_name: "Lume", company_domain: "lume.co",
                      segment: :nonprofit) ])
      described_class.call

      expect(Sendoff::Company.find_by(domain: "lume.co").segment).to eq("nonprofit")
    end
  end

  describe "skiplist" do
    it "skips a personal domain and creates nothing for it" do
      use_source([ ld(email: "someone@gmail.com", full_name: "Some One") ])
      stats = described_class.call

      expect(stats[:skipped]).to eq(1)
      expect(Sendoff::Lead.count).to eq(0)
      expect(Sendoff::Company.count).to eq(0)
    end
  end

  describe ".call class method" do
    it "delegates to an instance" do
      use_source([])
      expect(described_class.call).to be_a(Hash)
    end
  end
end
