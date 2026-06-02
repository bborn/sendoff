require "rails_helper"

module Sendoff
  RSpec.describe SegmentClassifier do
    def company_for(name:, domain:)
      Company.new(name: name, domain: domain)
    end

    it "classifies media/agency domains as agency" do
      c = company_for(name: "Bright Co", domain: "brightmedia.com")
      expect(described_class.classify(c)).to eq(:agency)
    end

    it "classifies a marketing-agency summary hint as agency" do
      c = company_for(name: "Stars Inc", domain: "starsinc.com")
      expect(described_class.classify(c, summary: "a marketing agency for small brands")).to eq(:agency)
    end

    it "classifies a .org TLD as nonprofit" do
      c = company_for(name: "Anyplace", domain: "anyplace.org")
      expect(described_class.classify(c)).to eq(:nonprofit)
    end

    it "classifies a foundation/association name as nonprofit" do
      c = company_for(name: "Cedarvale Foundation", domain: "cedarvale.com")
      expect(described_class.classify(c)).to eq(:nonprofit)
    end

    it "falls back to brand" do
      c = company_for(name: "Acme Widgets", domain: "acmewidgets.com")
      expect(described_class.classify(c)).to eq(:brand)
    end

    it "returns a reason alongside the segment" do
      c = company_for(name: "Acme Widgets", domain: "acmewidgets.com")
      seg, reason = described_class.classify_with_reason(c)
      expect(seg).to eq(:brand)
      expect(reason).to eq("brand_default")
    end
  end
end
