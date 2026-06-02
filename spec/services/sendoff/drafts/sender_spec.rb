require "rails_helper"

RSpec.describe Sendoff::Drafts::Sender do
  let(:company) { create(:company, :preset_segment, segment: "brand") }
  let(:lead)    { create(:lead, company: company, email: "casey@client.com") }
  let(:account) { create(:email_account, :outreach, email: "dana@acme.test", display_name: "Dana Lee") }
  let(:pipeline_entry) do
    Sendoff::PipelineEntry.skip_draft_callbacks do
      create(:pipeline_entry, lead: lead, company: company, stage: "review")
    end
  end
  let(:draft) do
    create(:draft, lead: lead, email_account: account, pipeline_entry: pipeline_entry,
                   to_addr: "casey@client.com", subject: "Quick question",
                   body_html: "<p>Hi Casey</p>", gmail_thread_id: "thread-1")
  end

  # gmail_client_for builds a fresh fake per call, so for assertions we pin the
  # factory to one persistent FakeClient and inspect its recorded calls.
  describe "immediate send (happy path)" do
    it "sends via Gmail, marks sent, advances pipeline, records EmailEvent + AuditLog" do
      fake = Sendoff::Gmail::FakeClient.new(account)
      Sendoff.config.gmail_client_factory = ->(_a) { fake }

      result = described_class.call(draft, immediate: true)

      expect(result).to eq(fake.sent_messages.last[:id])
      expect(fake.sent_messages.size).to eq(1)
      expect(fake.sent_messages.last).to include(to: "casey@client.com", subject: "Quick question", thread_id: "thread-1")

      expect(draft.reload).to be_sent
      expect(draft.sent_at).to be_present
      expect(pipeline_entry.reload.stage).to eq("contacted")

      ee = Sendoff::EmailEvent.last
      expect(ee.direction).to eq("outbound")
      expect(ee.to_addrs).to eq([ "casey@client.com" ])
      expect(ee.from_addr).to eq("dana@acme.test")

      audit = Sendoff::AuditLog.where(action: "sent").last
      expect(audit).to be_present
      expect(audit.recipient).to eq("casey@client.com")
    end

    it "applies persona default cc/bcc when the draft carries none" do
      Sendoff.config.persona = Sendoff::Persona.new(
        product_name: "Acme", sender_name: "Dana", sender_email: "dana@acme.test",
        default_cc: [ "founder@acme.test" ], default_bcc: [ "log@acme.test" ]
      )
      fake = Sendoff::Gmail::FakeClient.new(account)
      Sendoff.config.gmail_client_factory = ->(_a) { fake }

      described_class.call(draft, immediate: true)

      expect(fake.sent_messages.last).to include(cc: "founder@acme.test", bcc: "log@acme.test")
      ee = Sendoff::EmailEvent.last
      expect(ee.cc_addrs).to eq([ "founder@acme.test" ])
      expect(ee.bcc_addrs).to eq([ "log@acme.test" ])
    end
  end

  describe "rate limits" do
    let!(:fake) do
      f = Sendoff::Gmail::FakeClient.new(account)
      Sendoff.config.gmail_client_factory = ->(_a) { f }
      f
    end

    def outbound_event(to:, sent_at:)
      create(:email_event, lead: lead, company: company, direction: "outbound",
             email_account: account, from_addr: account.email, to_addrs: [ to ],
             sent_at: sent_at)
    end

    it "raises when the daily cap is hit" do
      Sendoff.config.send_daily_cap  = 1
      Sendoff.config.send_hourly_cap = 50
      outbound_event(to: "other@x.com", sent_at: 2.hours.ago)

      expect { described_class.call(draft, immediate: true) }
        .to raise_error(Sendoff::Drafts::RateLimitExceeded, /last 24h/)
    end

    it "raises when the hourly cap is hit" do
      Sendoff.config.send_daily_cap  = 50
      Sendoff.config.send_hourly_cap = 1
      outbound_event(to: "other@x.com", sent_at: 10.minutes.ago)

      expect { described_class.call(draft, immediate: true) }
        .to raise_error(Sendoff::Drafts::RateLimitExceeded, /last hour/)
    end

    it "raises when the recipient is within the cooldown window" do
      Sendoff.config.send_daily_cap        = 50
      Sendoff.config.send_hourly_cap       = 50
      Sendoff.config.recipient_cooldown_days = 7
      outbound_event(to: "casey@client.com", sent_at: 2.days.ago)

      expect { described_class.call(draft, immediate: true) }
        .to raise_error(Sendoff::Drafts::RateLimitExceeded, /casey@client\.com/)
    end

    it "allows the send when caps and cooldown are clear" do
      Sendoff.config.send_daily_cap        = 50
      Sendoff.config.send_hourly_cap       = 50
      Sendoff.config.recipient_cooldown_days = 7

      expect { described_class.call(draft, immediate: true) }.not_to raise_error
      expect(fake.sent_messages.size).to eq(1)
    end
  end

  describe "async path" do
    around do |ex|
      old = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      ex.run
      ActiveJob::Base.queue_adapter = old
    end

    it "enqueues a DeliverJob with a 60s hold and marks the draft sending" do
      expect {
        result = described_class.call(draft, immediate: false)
        expect(result).to eq(:queued)
      }.to have_enqueued_job(Sendoff::Drafts::DeliverJob).with(draft.id)

      expect(draft.reload).to be_sending
    end
  end

  describe "validation" do
    it "raises if the draft has no email_account" do
      draft.update_column(:email_account_id, nil)
      expect { described_class.new(draft.reload) }.to raise_error(ArgumentError, /email_account/)
    end
  end

  describe "protected stages" do
    it "does not regress a replied entry" do
      replied_entry = Sendoff::PipelineEntry.skip_draft_callbacks do
        create(:pipeline_entry, lead: lead, company: company, stage: "replied")
      end
      protected_draft = create(:draft, lead: lead, email_account: account,
                               pipeline_entry: replied_entry, to_addr: "casey@client.com")
      fake = Sendoff::Gmail::FakeClient.new(account)
      Sendoff.config.gmail_client_factory = ->(_a) { fake }

      described_class.call(protected_draft, immediate: true)

      expect(replied_entry.reload.stage).to eq("replied")
    end
  end
end
