require "rails_helper"
require "mail"

module Sendoff
  module InboundEmail
    RSpec.describe Ingest do
      # Build a raw RFC822 message with the `mail` gem, then reduce it to the
      # normalized Hash the controller would hand to the service.
      def parsed_from(from:, to:, subject: "Hello", text: "Body text",
                      message_id: nil, in_reply_to: nil, references: nil, date: Time.utc(2026, 6, 1, 12))
        mail = Mail.new do
          from    from
          to      to
          subject subject
          body    text
          date    date
        end
        mail.message_id = message_id if message_id
        mail.in_reply_to = in_reply_to if in_reply_to
        mail.references = references if references

        m = Mail.new(mail.to_s)
        {
          message_id: m.message_id ? "<#{m.message_id}>" : nil,
          from: m.from&.first,
          to: Array(m.to),
          cc: Array(m.cc),
          bcc: Array(m.bcc),
          subject: m.subject,
          text: m.body&.decoded,
          html: nil,
          in_reply_to: m.header["In-Reply-To"]&.value,
          references: m.header["References"]&.value,
          date: m.date&.to_time
        }
      end

      describe ".call" do
        it "records an OUTBOUND event when From is one of our accounts and matches the To lead" do
          account = create(:email_account, email: "rep@ourco.com")
          company = create(:company)
          lead = create(:lead, company: company, email: "buyer@acme.com")

          parsed = parsed_from(from: "rep@ourco.com", to: "buyer@acme.com",
                               message_id: "<out-1@ourco.com>")

          event = described_class.call(parsed)

          expect(event).to be_persisted
          expect(event.direction).to eq("outbound")
          expect(event.email_account).to eq(account)
          expect(event.lead).to eq(lead)
          expect(event.company).to eq(company)
          expect(event.from_addr).to eq("rep@ourco.com")
          expect(event.to_addrs).to include("buyer@acme.com")
          expect(event.gmail_message_id).to eq("<out-1@ourco.com>")
        end

        it "records an INBOUND event when From is an external lead replying to our account" do
          create(:email_account, email: "rep@ourco.com")
          company = create(:company)
          lead = create(:lead, company: company, email: "buyer@acme.com")

          parsed = parsed_from(from: "buyer@acme.com", to: "rep@ourco.com",
                               message_id: "<in-1@acme.com>")

          event = described_class.call(parsed)

          expect(event.direction).to eq("inbound")
          expect(event.email_account).to be_nil
          expect(event.lead).to eq(lead)
          expect(event.company).to eq(company)
          expect(event.from_addr).to eq("buyer@acme.com")
        end

        it "is idempotent on Message-ID (calling twice yields one event)" do
          create(:email_account, email: "rep@ourco.com")
          create(:lead, email: "buyer@acme.com")

          parsed = parsed_from(from: "rep@ourco.com", to: "buyer@acme.com",
                               message_id: "<dup-1@ourco.com>")

          first = described_class.call(parsed)
          second = described_class.call(parsed)

          expect(second.id).to eq(first.id)
          expect(EmailEvent.where(gmail_message_id: "<dup-1@ourco.com>").count).to eq(1)
        end

        it "records the event with nil lead/company when the counterpart is unmatched" do
          create(:email_account, email: "rep@ourco.com")

          parsed = parsed_from(from: "rep@ourco.com", to: "stranger@nowhere.com",
                               message_id: "<orphan-1@ourco.com>")

          expect { @event = described_class.call(parsed) }.not_to raise_error
          expect(@event).to be_persisted
          expect(@event.lead).to be_nil
          expect(@event.company).to be_nil
          expect(@event.direction).to eq("outbound")
        end

        it "derives thread_id from In-Reply-To when present, else the Message-ID" do
          create(:email_account, email: "rep@ourco.com")
          create(:lead, email: "buyer@acme.com")

          threaded = parsed_from(from: "buyer@acme.com", to: "rep@ourco.com",
                                 message_id: "<reply-1@acme.com>",
                                 in_reply_to: "<orig-1@ourco.com>")
          standalone = parsed_from(from: "buyer@acme.com", to: "rep@ourco.com",
                                   message_id: "<solo-1@acme.com>")

          expect(described_class.call(threaded).gmail_thread_id).to eq("<orig-1@ourco.com>")
          expect(described_class.call(standalone).gmail_thread_id).to eq("<solo-1@acme.com>")
        end

        it "writes an audit log entry" do
          create(:email_account, email: "rep@ourco.com")
          lead = create(:lead, email: "buyer@acme.com")

          parsed = parsed_from(from: "rep@ourco.com", to: "buyer@acme.com",
                               message_id: "<audit-1@ourco.com>")

          expect { described_class.call(parsed) }
            .to change { AuditLog.where(action: "inbound_email_recorded").count }.by(1)

          log = AuditLog.where(action: "inbound_email_recorded").last
          expect(log.subject).to eq(lead)
        end
      end
    end
  end
end
