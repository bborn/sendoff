require "rails_helper"

module Sendoff
  module Gmail
    RSpec.describe Client do
      let(:account) { create(:email_account) }

      it "requires an EmailAccount" do
        expect { described_class.new("not-an-account") }.to raise_error(ArgumentError)
        expect { described_class.new(account) }.not_to raise_error
      end

      describe ".dry_run?" do
        it "reflects ENV['GMAIL_DRY_RUN']" do
          expect(described_class.dry_run?).to be(false)
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("GMAIL_DRY_RUN").and_return("true")
          expect(described_class.dry_run?).to be(true)
        end
      end

      describe "dry-run write safety" do
        before do
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("GMAIL_DRY_RUN").and_return("true")
        end

        it "returns a fake id from create_draft without hitting the network" do
          client = described_class.new(account)
          expect(client.create_draft(to: "a@b.com", subject: "S", body_html: "<p>B</p>"))
            .to start_with("DRYRUN-DRAFT-")
        end

        it "blocks send_message" do
          client = described_class.new(account)
          expect { client.send_message(to: "a@b.com", subject: "S", body_html: "<p>B</p>") }
            .to raise_error(/dry-run/)
        end

        it "returns empty reads in dry-run" do
          client = described_class.new(account)
          expect(client.search_threads(query: "x")).to eq([])
          expect(client.fetch_recent_sent).to eq([])
        end
      end

      describe ".excluded_recipient_domains" do
        it "defaults to none when config does not expose it" do
          expect(described_class.excluded_recipient_domains).to eq([])
        end

        it "reads from config when available" do
          cfg = Struct.new(:excluded_recipient_domains).new(%w[internal.example])
          allow(Sendoff).to receive(:config).and_return(cfg)
          expect(described_class.excluded_recipient_domains).to eq(%w[internal.example])
        end
      end
    end
  end
end
