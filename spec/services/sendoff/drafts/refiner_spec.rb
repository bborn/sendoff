require "rails_helper"

RSpec.describe Sendoff::Drafts::Refiner do
  let(:company) { create(:company, :preset_segment, segment: "brand") }
  let(:lead)    { create(:lead, company: company, email: "casey@client.com") }
  let(:account) { create(:email_account, :outreach, email: "dana@acme.test", display_name: "Dana Lee") }
  let(:draft) do
    create(:draft, lead: lead, email_account: account, intent: "cold",
           to_addr: "casey@client.com", subject: "Original subject",
           body_html: "<p>Original body</p>", original_subject: "Original subject",
           original_body_html: "<p>Original body</p>")
  end

  describe "rewrite via the LLM" do
    it "revises subject + body and resets the human-edited baseline" do
      Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: [
        { subject: "Tighter subject", body_html: "<p>Tighter body</p>" }.to_json, # revise
        { subject: "Tighter subject", body_html: "<p>Tighter body</p>" }.to_json  # voice critic
      ])

      result = described_class.call(draft, feedback: "make it shorter")

      expect(result[:subject]).to eq("Tighter subject")
      expect(draft.reload.subject).to eq("Tighter subject")
      expect(draft.body_html).to eq("<p>Tighter body</p>")
      expect(draft.original_subject).to eq("Tighter subject")
      expect(draft.human_edited).to be(false)
    end
  end

  describe "rule-like feedback" do
    it "creates a VoiceRule attributed to the current actor" do
      Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new { |prompt|
        if prompt.include?("Distill this feedback")
          { rule: "Never use exclamation points." }.to_json
        else
          { subject: "S", body_html: "<p>B</p>" }.to_json
        end
      }
      Sendoff::Current.actor = "reviewer@acme.test"

      expect {
        described_class.call(draft, feedback: "Never use exclamation points")
      }.to change { Sendoff::VoiceRule.count }.by(1)

      rule = Sendoff::VoiceRule.last
      expect(rule.rule).to eq("Never use exclamation points.")
      expect(rule.raw_feedback).to eq("Never use exclamation points")
      expect(rule.created_by).to eq("reviewer@acme.test")
      expect(rule.scope).to eq("all")
    ensure
      Sendoff::Current.reset
    end

    it "does not create a VoiceRule for non-rule feedback" do
      Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: [
        { subject: "S", body_html: "<p>B</p>" }.to_json,
        { subject: "S", body_html: "<p>B</p>" }.to_json
      ])

      expect {
        described_class.call(draft, feedback: "this looks great, ship it")
      }.not_to change { Sendoff::VoiceRule.count }
    end
  end

  describe "sender switch" do
    let(:new_account) { create(:email_account, :outreach, email: "sam@acme.test", display_name: "Sam Smith") }

    it "rebuilds the Gmail draft, clears the thread, and logs the change" do
      old_fake = Sendoff::Gmail::FakeClient.new(account)
      new_fake = Sendoff::Gmail::FakeClient.new(new_account)
      Sendoff.config.gmail_client_factory = ->(a) { a == new_account ? new_fake : old_fake }
      Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: [
        { subject: "S", body_html: "<p>B</p>" }.to_json,
        { subject: "S", body_html: "<p>B</p>" }.to_json
      ])
      draft.update_columns(gmail_draft_id: "old-draft-id", gmail_thread_id: "old-thread")

      described_class.call(draft, feedback: "move to Sam", email_account: new_account)

      expect(draft.reload.email_account).to eq(new_account)
      expect(draft.gmail_thread_id).to be_nil
      expect(new_fake.created_drafts.size).to eq(1)
      expect(old_fake.deleted_drafts).to include("old-draft-id")
      expect(Sendoff::AuditLog.where(action: "draft_sender_changed")).to exist
    end
  end
end
