require "rails_helper"

module Sendoff
  RSpec.describe Note, type: :model do
    it "has a valid factory" do
      expect(build(:note)).to be_valid
    end

    it "requires a body_md" do
      expect(build(:note, body_md: nil)).not_to be_valid
    end

    it "is polymorphic over notable" do
      lead_note = create(:note, :on_lead)
      expect(lead_note.notable).to be_a(Lead)

      company_note = create(:note)
      expect(company_note.notable).to be_a(Company)
    end
  end
end
