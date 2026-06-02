require "rails_helper"

module Sendoff
  RSpec.describe EmailEvent, type: :model do
    it "has a valid factory" do
      expect(build(:email_event)).to be_valid
    end

    describe "validations" do
      it { expect(build(:email_event, direction: nil)).not_to be_valid }
      it { expect(build(:email_event, from_addr: nil)).not_to be_valid }
      it { expect(build(:email_event, sent_at: nil)).not_to be_valid }
    end

    describe "direction enum" do
      it { expect(EmailEvent.directions.keys).to match_array(%w[inbound outbound]) }
    end

    describe "optional associations" do
      it "is valid without lead/company/email_account" do
        expect(build(:email_event, lead: nil, company: nil, email_account: nil)).to be_valid
      end
    end
  end
end
