require "rails_helper"

module Sendoff
  RSpec.describe CompetitorDomain, type: :model do
    it "has a valid factory" do
      expect(build(:competitor_domain)).to be_valid
    end

    describe "validations" do
      it "requires a category in CATEGORIES" do
        expect(build(:competitor_domain, category: "bogus")).not_to be_valid
        expect(build(:competitor_domain, category: "adjacent")).to be_valid
      end

      it "requires a case-insensitively unique domain" do
        create(:competitor_domain, domain: "rival.com")
        expect(build(:competitor_domain, domain: "RIVAL.COM")).not_to be_valid
      end
    end

    describe "normalization" do
      it "downcases and strips the domain before validation" do
        cd = create(:competitor_domain, domain: "  Rival.COM ")
        expect(cd.domain).to eq("rival.com")
      end
    end
  end
end
