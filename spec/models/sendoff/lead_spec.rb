require "rails_helper"

module Sendoff
  RSpec.describe Lead, type: :model do
    it "has a valid factory" do
      expect(build(:lead)).to be_valid
    end

    describe "validations" do
      it "requires an email" do
        expect(build(:lead, email: nil)).not_to be_valid
      end

      it "rejects a malformed email" do
        expect(build(:lead, email: "not-an-email")).not_to be_valid
      end

      it "requires a unique email" do
        create(:lead, email: "dup@example.com")
        expect(build(:lead, email: "dup@example.com")).not_to be_valid
      end
    end

    describe "associations" do
      it "has the expected associations" do
        expect(Lead.reflect_on_association(:company).macro).to eq(:belongs_to)
        expect(Lead.reflect_on_association(:pipeline_entries).macro).to eq(:has_many)
        expect(Lead.reflect_on_association(:drafts).macro).to eq(:has_many)
        expect(Lead.reflect_on_association(:hidden_lead).macro).to eq(:has_one)
      end
    end

    describe "name_source enum" do
      it "drops the legacy CRM name_source value" do
        expect(Lead.name_sources.keys).to match_array(%w[manual email_prefix enriched unknown])
      end
    end

    describe "#display_name" do
      it "prefers full_name, then first_name, then email" do
        expect(build(:lead, full_name: "Full Name").display_name).to eq("Full Name")
        expect(build(:lead, full_name: nil, first_name: "First").display_name).to eq("First")
        expect(build(:lead, full_name: nil, first_name: nil, email: "x@example.com").display_name).to eq("x@example.com")
      end
    end

    describe "#hidden?" do
      it "reflects the presence of a hidden_lead" do
        lead = create(:lead)
        expect(lead.hidden?).to be(false)
        create(:hidden_lead, lead: lead)
        expect(lead.reload.hidden?).to be(true)
      end
    end

    describe "#enrichable?" do
      it "is true when the name is weak (name_source=email_prefix)" do
        lead = create(:lead, name_source: "email_prefix", first_name: "Kearns")
        expect(lead.enrichable?).to be(true)
      end

      it "is true when first_name is blank regardless of name_source" do
        lead = create(:lead, name_source: "enriched", first_name: nil, full_name: nil)
        expect(lead.enrichable?).to be(true)
      end

      it "is false for a verified name (name_source=enriched with a first name)" do
        lead = create(:lead, name_source: "enriched", first_name: "Dana", full_name: "Dana Okafor")
        expect(lead.enrichable?).to be(false)
      end

      it "is false for a manually-set name" do
        lead = create(:lead, name_source: "manual", first_name: "Sam", full_name: "Sam Lee")
        expect(lead.enrichable?).to be(false)
      end

      it "is false when a research note already exists" do
        lead = create(:lead, name_source: "email_prefix", first_name: "Kearns")
        create(:note, :on_lead, notable: lead, title: "Research Summary (auto)", body_md: "done")
        expect(lead.reload.enrichable?).to be(false)
      end

      it "is false when the lead is hidden" do
        lead = create(:lead, name_source: "email_prefix", first_name: "Kearns")
        create(:hidden_lead, lead: lead)
        expect(lead.reload.enrichable?).to be(false)
      end
    end
  end
end
