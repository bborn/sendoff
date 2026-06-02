require "rails_helper"

RSpec.describe Sendoff::DraftJob do
  let(:persona) do
    Sendoff::Persona.new(
      product_name: "Acme Analytics", sender_name: "Dana Lee",
      sender_email: "dana@acme.test",
      default_cc: [ "founder@acme.test" ], default_bcc: [ "log@acme.test" ]
    )
  end
  let(:company) { create(:company, :preset_segment, segment: "brand", domain: "client.com") }
  let(:lead) do
    create(:lead, company: company, email: "jordan@client.com",
           first_name: "Jordan", last_name: "Rivera", full_name: "Jordan Rivera",
           name_source: "manual", created_at: 30.days.ago)
  end
  let!(:account) { create(:email_account, :outreach, email: "dana@acme.test", display_name: "Dana Lee") }
  let(:entry) do
    Sendoff::PipelineEntry.skip_draft_callbacks do
      create(:pipeline_entry, lead: lead, company: company, stage: "drafting")
    end
  end

  before { Sendoff.config.persona = persona }

  def fake_llm(responses)
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: responses)
  end

  describe "happy path" do
    let(:draft_json) do
      { subject: "quick question on reporting",
        body_html: "<p>Hi Jordan,</p><p>I noticed your team and wanted to reach out.</p>",
        intent: "cold", name_used: "Jordan", skip_reason: nil }.to_json
    end

    it "persists a Draft, creates a Gmail draft, advances entry to review, logs" do
      fake = Sendoff::Gmail::FakeClient.new(account)
      Sendoff.config.gmail_client_factory = ->(_a) { fake }
      # Drafter -> VoiceCritic -> HallucinationCritic each call complete once.
      fake_llm([
        draft_json,
        { subject: "quick question on reporting",
          body_html: "<p>Hi Jordan,</p><p>I noticed your team and wanted to reach out.</p>" }.to_json,
        { ok: true, flagged_claims: [] }.to_json
      ])

      expect {
        described_class.new.perform(entry.id, intent: :auto)
      }.to change { Sendoff::Draft.count }.by(1)

      draft = Sendoff::Draft.last
      expect(draft.lead).to eq(lead)
      expect(draft.email_account).to eq(account)
      expect(draft.intent).to eq("cold")
      expect(draft.cc_addr).to eq("founder@acme.test")
      expect(draft.bcc_addr).to eq("log@acme.test")
      expect(draft.gmail_draft_id).to eq(fake.created_drafts.last[:id])

      expect(entry.reload.stage).to eq("review")
      expect(Sendoff::AuditLog.where(action: "drafted")).to exist
    end
  end

  describe "skip path" do
    it "sets stage to dud and writes an AuditLog for a generic skip" do
      # name_unknown skip: blank first name + email_prefix source.
      lead.update_columns(first_name: nil, full_name: nil, name_source: "email_prefix")

      expect {
        described_class.new.perform(entry.id, intent: :auto)
      }.not_to change { Sendoff::Draft.count }

      expect(entry.reload.stage).to eq("dud")
      skip_log = Sendoff::AuditLog.where(action: "draft_skipped").last
      expect(skip_log).to be_present
      expect(skip_log.detail).to include("name_unknown")
    end

    it "maps recent_inbound_awaiting_response to the replied stage" do
      # Seed a recent inbound Gmail message so the Drafter's recent-inbound guard fires.
      fake = Sendoff::Gmail::FakeClient.new(account)
      fake.messages = [ {
        direction: "inbound", sent_at: 2.days.ago, gmail_thread_id: "t1",
        subject: "Re: hi", account_email: account.email
      } ]
      Sendoff.config.gmail_client_factory = ->(_a) { fake }

      described_class.new.perform(entry.id, intent: :auto)

      expect(entry.reload.stage).to eq("replied")
      expect(Sendoff::AuditLog.where(action: "draft_skipped").last.detail)
        .to include("recent_inbound_awaiting_response")
    end
  end
end
