require "rails_helper"

module Sendoff
  RSpec.describe Draft, type: :model do
    it "has a valid factory" do
      expect(build(:draft)).to be_valid
    end

    describe "validations" do
      it { expect(build(:draft, to_addr: nil)).not_to be_valid }
      it { expect(build(:draft, subject: nil)).not_to be_valid }
      it { expect(build(:draft, body_html: nil)).not_to be_valid }
      it { expect(build(:draft, status: nil)).not_to be_valid }
    end

    describe "enums" do
      it "exposes the status set" do
        expect(Draft.statuses.keys).to match_array(%w[pending sending scheduled sent flagged discarded])
      end

      it "includes auto in the intent set" do
        expect(Draft.intents.keys).to include("auto")
        expect(Draft.intents.keys).to match_array(%w[cold reengage checkin followup auto])
      end

      it "allows a nil intent" do
        expect(build(:draft, intent: nil)).to be_valid
      end

      it "exposes name_confidence without the legacy CRM value" do
        expect(Draft.name_confidences.keys).to match_array(%w[research_verified email_prefix rescued_by_research])
      end
    end

    describe "scopes" do
      it "pending_review returns pending drafts newest first" do
        old = create(:draft, :pending, created_at: 2.days.ago)
        recent = create(:draft, :pending, created_at: 1.hour.ago)
        create(:draft, :sent)
        expect(Draft.pending_review.to_a).to eq([ recent, old ])
      end

      it "hallucination_flagged returns drafts with flagged claims" do
        flagged = create(:draft, :hallucination_flagged)
        create(:draft)
        expect(Draft.hallucination_flagged).to contain_exactly(flagged)
      end
    end

    describe "#hallucination_flagged?" do
      it "is true with claims present" do
        expect(build(:draft, :hallucination_flagged).hallucination_flagged?).to be(true)
      end

      it "is false with no claims" do
        expect(build(:draft, flagged_claims: nil).hallucination_flagged?).to be(false)
      end
    end
  end
end
