require "rails_helper"

module Sendoff
  module Gmail
    RSpec.describe FakeClient do
      let(:account) { build(:email_account) }
      subject(:client) { described_class.new(account) }

      it "accepts an email_account argument" do
        expect(client.account).to eq(account)
      end

      describe "reads default to empty" do
        it "returns empty threads/messages/recent_sent" do
          expect(client.search_threads(query: "x")).to eq([])
          expect(client.fetch_messages_for(email_address: "a@b.com")).to eq([])
          expect(client.fetch_messages_for_domain(domain: "b.com")).to eq([])
          expect(client.fetch_recent_sent).to eq([])
          expect(client.get_message_body("m1")).to eq("")
        end

        it "can be primed with canned messages" do
          client.messages = [ { id: "m1", subject: "Hi" } ]
          expect(client.fetch_messages_for(email_address: "a@b.com")).to eq([ { id: "m1", subject: "Hi" } ])
        end
      end

      describe "writes are recorded" do
        it "records create_draft and returns a fake id" do
          id = client.create_draft(to: "a@b.com", subject: "S", body_html: "<p>B</p>")
          expect(id).to eq("FAKE-DRAFT-1")
          expect(client.created_drafts.last).to include(to: "a@b.com", subject: "S")
        end

        it "records send_message and returns a fake id" do
          id = client.send_message(to: "a@b.com", subject: "S", body_html: "<p>B</p>", bcc: "log@b.com")
          expect(id).to eq("FAKE-SENT-1")
          expect(client.sent_messages.last).to include(to: "a@b.com", bcc: "log@b.com")
        end

        it "records delete_draft" do
          client.delete_draft("d1")
          expect(client.deleted_drafts).to eq([ "d1" ])
        end
      end

      it "matches the Client public method surface" do
        surface = %i[
          search_threads thread_summary get_message_body create_draft send_message
          delete_draft fetch_messages_for fetch_messages_for_domain
          search_messages_content fetch_sent_body_from_thread fetch_recent_sent
        ]
        surface.each { |m| expect(client).to respond_to(m) }
      end
    end
  end
end
