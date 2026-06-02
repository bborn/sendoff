require "rails_helper"

module Sendoff
  RSpec.describe EmailAccount, type: :model do
    it "has a valid factory" do
      expect(build(:email_account)).to be_valid
    end

    describe "validations" do
      it "requires a well-formed unique email" do
        create(:email_account, email: "a@example.com")
        expect(build(:email_account, email: "a@example.com")).not_to be_valid
        expect(build(:email_account, email: "bad")).not_to be_valid
      end

      it "requires a display_name" do
        expect(build(:email_account, display_name: nil)).not_to be_valid
      end
    end

    describe "role enum" do
      it { expect(EmailAccount.roles.keys).to match_array(%w[outreach personal shared]) }
    end

    describe "scopes" do
      it "for_outreach returns active outreach and shared accounts" do
        outreach = create(:email_account, :outreach)
        shared   = create(:email_account, :shared)
        create(:email_account, :personal)
        create(:email_account, :outreach, :inactive)
        expect(EmailAccount.for_outreach).to contain_exactly(outreach, shared)
      end
    end

    describe "encryption" do
      it "encrypts oauth_refresh_token at rest" do
        account = create(:email_account, oauth_refresh_token: "secret-token")
        raw = EmailAccount.connection.select_value(
          "SELECT oauth_refresh_token FROM sendoff_email_accounts WHERE id = '#{account.id}'"
        )
        expect(raw).not_to include("secret-token")
        expect(account.reload.oauth_refresh_token).to eq("secret-token")
      end
    end

    describe "#default_first_name" do
      it "derives first_name from display_name" do
        account = build(:email_account, display_name: "Dana Sender", first_name: nil)
        account.valid?
        expect(account.first_name).to eq("Dana")
      end
    end

    describe "#to_s" do
      it "renders display name and email" do
        expect(build(:email_account, display_name: "Dana", email: "d@example.com").to_s).to eq("Dana <d@example.com>")
      end
    end
  end
end
