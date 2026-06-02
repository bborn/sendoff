require "rails_helper"

module Sendoff
  RSpec.describe Company, type: :model do
    it "has a valid factory" do
      expect(build(:company)).to be_valid
    end

    describe "validations" do
      it "requires a name" do
        expect(build(:company, name: nil)).not_to be_valid
      end

      it "requires a domain" do
        expect(build(:company, domain: nil)).not_to be_valid
      end

      it "requires a unique domain" do
        create(:company, domain: "dup.com")
        expect(build(:company, domain: "dup.com")).not_to be_valid
      end
    end

    describe "associations" do
      it "has the expected associations" do
        expect(Company.reflect_on_association(:leads).macro).to eq(:has_many)
        expect(Company.reflect_on_association(:pipeline_entries).macro).to eq(:has_many)
        expect(Company.reflect_on_association(:notes).macro).to eq(:has_many)
        expect(Company.reflect_on_association(:notes).options[:as]).to eq(:notable)
      end

      it "destroys dependent leads" do
        company = create(:company)
        create(:lead, company: company)
        expect { company.destroy }.to change(Lead, :count).by(-1)
      end
    end

    describe "segment enum" do
      it "accepts the generic example segments" do
        expect(Company.segments.keys).to match_array(%w[agency brand nonprofit unknown])
      end
    end

    describe "auto_classify_segment on create" do
      it "classifies a .org domain as nonprofit" do
        company = create(:company, :nonprofit, segment: nil)
        expect(company.reload.segment).to eq("nonprofit")
        expect(company.segment_source).to start_with("auto:")
      end

      it "classifies an agency domain as agency" do
        company = create(:company, :agency, segment: nil)
        expect(company.reload.segment).to eq("agency")
      end

      it "falls back to brand for a generic domain" do
        company = create(:company, name: "Acme Co", domain: "acmewidgets.com", segment: nil)
        expect(company.reload.segment).to eq("brand")
      end

      it "does not reclassify a preset non-unknown segment" do
        company = create(:company, :nonprofit, segment: "brand")
        expect(company.reload.segment).to eq("brand")
      end
    end

    describe "#segment_label" do
      it "titleizes the segment" do
        expect(build(:company, segment: "agency").segment_label).to eq("Agency")
      end
    end
  end
end
