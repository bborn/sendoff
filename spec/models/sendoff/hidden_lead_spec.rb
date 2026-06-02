require "rails_helper"

module Sendoff
  RSpec.describe HiddenLead, type: :model do
    it "has a valid factory" do
      expect(build(:hidden_lead)).to be_valid
    end

    it "belongs to a lead" do
      expect(HiddenLead.reflect_on_association(:lead).macro).to eq(:belongs_to)
    end

    it "enforces one hidden record per lead" do
      lead = create(:lead)
      create(:hidden_lead, lead: lead)
      expect(build(:hidden_lead, lead: lead)).not_to be_valid
    end
  end
end
