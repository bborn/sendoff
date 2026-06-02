require "rails_helper"

module Sendoff
  module Gmail
    RSpec.describe History do
      let(:account) { create(:email_account) }
      let(:lead)    { create(:lead) }

      it "obtains its client via config.gmail_client_for and returns messages" do
        fake = FakeClient.new(account)
        fake.messages = [ { id: "m1", sent_at: Time.current, subject: "Recent" } ]
        allow(Sendoff.config).to receive(:gmail_client_for).and_return(fake)

        result = described_class.for_lead(lead, accounts: [ account ])
        expect(result[:messages].map { |m| m[:id] }).to include("m1")
      end

      it "returns an empty message set when accounts have no history" do
        # rails_helper wires gmail_client_factory to FakeClient (empty by default).
        result = described_class.for_lead(lead, accounts: [ account ])
        expect(result[:messages]).to eq([])
        expect(result[:timed_out]).to eq([])
      end

      it "for_domain delegates to the per-account domain fetch" do
        fake = FakeClient.new(account)
        fake.messages = [ { id: "d1", sent_at: Time.current } ]
        allow(Sendoff.config).to receive(:gmail_client_for).and_return(fake)

        result = described_class.for_domain("example.com", accounts: [ account ])
        expect(result[:messages].map { |m| m[:id] }).to include("d1")
      end

      it "sorts merged messages newest first" do
        a1 = create(:email_account, email: "a1@example.com")
        a2 = create(:email_account, email: "a2@example.com")

        older = FakeClient.new(a1).tap { |c| c.messages = [ { id: "old", sent_at: 2.days.ago } ] }
        newer = FakeClient.new(a2).tap { |c| c.messages = [ { id: "new", sent_at: 1.hour.ago } ] }
        allow(Sendoff.config).to receive(:gmail_client_for) do |acct|
          acct == a1 ? older : newer
        end

        result = described_class.for_lead(lead, accounts: [ a1, a2 ])
        expect(result[:messages].map { |m| m[:id] }).to eq(%w[new old])
      end
    end
  end
end
