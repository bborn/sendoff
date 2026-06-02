require "rails_helper"

RSpec.describe Sendoff::Drafter do
  # A real, fully-fictional persona used across the drafter specs.
  let(:persona) do
    Sendoff::Persona.new(
      product_name:        "Acme Analytics",
      product_description: "a reporting tool for agencies",
      sender_name:         "Dana Lee",
      sender_email:        "dana@acme.test",
      voice_guide:         "Be direct, warm, and concise.",
      outreach_principles: "Lead with value. No fake discovery.",
      allowed_url_patterns: [ %r{\Ahttps://calendar\.acme\.test/} ],
      segment_prompt_hints: { "agency" => "Mention the agency launch program." }
    )
  end

  let(:company) { create(:company, :preset_segment, segment: "brand", domain: "client.com", name: "Client Co") }
  let(:lead) do
    # created_at well past lead_fresh_touch_days so the "too recent" guard
    # doesn't fire on the happy paths (specs that test that guard override this).
    create(:lead, company: company, email: "jordan@client.com",
                  first_name: "Jordan", last_name: "Rivera", full_name: "Jordan Rivera",
                  name_source: "manual", created_at: 30.days.ago)
  end

  before do
    Sendoff.config.persona = persona
    # An outreach account for the drafter to pick.
    create(:email_account, :outreach, email: "dana@acme.test", display_name: "Dana Lee")
  end

  def fake_llm(responses)
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: responses)
  end

  describe ".draft_for_lead — happy path" do
    it "returns a usable draft" do
      draft_json = {
        subject: "quick question on reporting",
        body_html: "<p>Hi Jordan, I wanted to reach out about your reporting setup.</p>",
        name_used: "Jordan",
        skip_reason: nil
      }.to_json
      # Drafter -> VoiceCritic -> HallucinationCritic, in order.
      critic_json = { subject: "quick question on reporting",
                      body_html: "<p>Hi Jordan, I wanted to reach out about your reporting setup.</p>" }.to_json
      halluc_json = { flagged_claims: [], reason: nil }.to_json
      fake_llm([ draft_json, critic_json, halluc_json ])

      result = described_class.draft_for_lead(lead, intent: :cold)

      expect(result.skip?).to be(false)
      expect(result.subject).to eq("quick question on reporting")
      expect(result.body_html).to include("Jordan")
      expect(result.email_account.email).to eq("dana@acme.test")
      expect(result.intent).to eq(:cold)
      expect(result.name_used).to eq("Jordan")
      expect(result.flagged_claims).to be_nil
      expect(result.name_confidence).to eq(:research_verified) # manual name_source -> high confidence
      expect(result.prompt_used).to be_present
    end

    it "builds the prompt from the persona with no host-specific strings" do
      fake_llm([ { subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])
      described_class.draft_for_lead(lead, intent: :cold)

      prompt = Sendoff.config.llm_client.prompts.first
      expect(prompt).to include("Acme Analytics")
      expect(prompt).to include("Dana Lee")
      # No foreign host brand leaks: only the configured persona's product appears.
      expect(prompt).to include(persona.product_name)
    end

    it "resolves :auto intent from the LLM response" do
      fake_llm([
        { intent: "cold", subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json
      ])
      result = described_class.draft_for_lead(lead, intent: :auto)
      expect(result.intent).to eq(:cold)
    end
  end

  describe "skip reasons" do
    it "skips when the name is unknown and no research verifies it" do
      lead.update!(name_source: "email_prefix", first_name: "")
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip?).to be(true)
      expect(result.skip_reason).to eq("name_unknown")
    end

    it "proceeds when name_source is unreliable but research verifies the name" do
      lead.update!(name_source: "email_prefix")
      create(:note, notable: lead, body_md: ("- Name: Jordan Rivera\n" + ("detail line. " * 40)))
      fake_llm([ { subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])

      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip?).to be(false)
      expect(result.name_confidence).to eq(:rescued_by_research)
    end

    it "skips personal email domains" do
      lead.update!(email: "jordan@gmail.com")
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip_reason).to eq("personal_email")
    end

    it "skips competitor-adjacent domains" do
      Sendoff::CompetitorDomain.create!(domain: "client.com", category: "direct")
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip_reason).to eq("competitor_adjacent")
    end

    it "skips when the lead replied to us recently (inbound)" do
      account = Sendoff::EmailAccount.first
      allow_any_instance_of(Sendoff::Gmail::FakeClient).to receive(:fetch_messages_for).and_return([
        { gmail_thread_id: "t1", account_email: account.email, account_name: "Dana Lee",
          direction: "inbound", subject: "Re: hi", sent_at: 3.days.ago }
      ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip_reason).to eq("recent_inbound_awaiting_response")
    end

    it "skips a too-recent first touch for cold intent" do
      lead.update!(created_at: 1.day.ago)
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip_reason).to eq("lead_too_recent_first_touch")
    end

    it "does not apply the too-recent guard to checkin intent" do
      lead.update!(created_at: 1.day.ago)
      fake_llm([ { subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])
      result = described_class.draft_for_lead(lead, intent: :checkin)
      expect(result.skip?).to be(false)
    end

    it "skips when the LLM itself returns a skip_reason" do
      fake_llm([ { skip_reason: "enrichment_indicates_skip" }.to_json ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip_reason).to eq("enrichment_indicates_skip")
    end

    it "skips when no outreach account is available" do
      Sendoff::EmailAccount.delete_all
      fake_llm([ { subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip_reason).to eq("no_email_account_available")
    end
  end

  describe "URL validation" do
    it "passes a body using an allowlisted URL" do
      body = "<p>Grab a time: https://calendar.acme.test/dana</p>"
      fake_llm([
        { subject: "s", body_html: body, name_used: "Jordan", skip_reason: nil }.to_json,
        { subject: "s", body_html: body }.to_json,
        { flagged_claims: [] }.to_json
      ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.skip?).to be(false)
      expect(result.body_html).to include("calendar.acme.test")
    end

    it "raises DisallowedUrlError for an off-allowlist URL" do
      body = "<p>See https://evil.example.com/phish</p>"
      fake_llm([
        { subject: "s", body_html: body, name_used: "Jordan", skip_reason: nil }.to_json,
        { subject: "s", body_html: body }.to_json
      ])
      expect {
        described_class.draft_for_lead(lead, intent: :cold)
      }.to raise_error(Sendoff::DisallowedUrlError, /evil\.example\.com/)
    end

    it "allows the account URL when an account is present" do
      account_info = Sendoff::Adapters::AccountInfo.new(
        subdomain: "client", account_url: "https://client.acme.test", status: "active"
      )
      allow(Sendoff.config.account_lookup).to receive(:find).with(lead).and_return(account_info)

      body = "<p>Your account: https://client.acme.test/dashboard</p>"
      fake_llm([
        { subject: "s", body_html: body, name_used: "Jordan", skip_reason: nil }.to_json,
        { subject: "s", body_html: body }.to_json,
        { flagged_claims: [] }.to_json
      ])
      result = described_class.draft_for_lead(lead, intent: :checkin)
      expect(result.skip?).to be(false)
      expect(result.body_html).to include("client.acme.test")
    end
  end

  describe "account-aware tone" do
    it "includes account context in the prompt when account_lookup returns info" do
      account_info = Sendoff::Adapters::AccountInfo.new(
        subdomain: "client", account_url: "https://client.acme.test",
        plan_name: "Pro", status: "active", looks_dormant: false, usage_label: "5 reports"
      )
      allow(Sendoff.config.account_lookup).to receive(:find).with(lead).and_return(account_info)
      fake_llm([ { subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])

      described_class.draft_for_lead(lead, intent: :checkin)
      prompt = Sendoff.config.llm_client.prompts.first
      expect(prompt).to include("<account>")
      expect(prompt).to include("client.acme.test")
      expect(prompt).to include("Pro")
    end
  end

  describe "hallucination flagging" do
    it "surfaces flagged claims on the result" do
      body = "<p>Hi Jordan, congrats on your 500 new partners.</p>"
      fake_llm([
        { subject: "s", body_html: body, name_used: "Jordan", skip_reason: nil }.to_json,
        { subject: "s", body_html: body }.to_json,
        { flagged_claims: [ "500 new partners" ], reason: "not in context" }.to_json
      ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.flagged_claims).to eq([ "500 new partners" ])
    end

    it "returns nil flagged_claims when the critic is disabled" do
      Sendoff.config.hallucination_critic_enabled = false
      body = "<p>Hi Jordan.</p>"
      fake_llm([
        { subject: "s", body_html: body, name_used: "Jordan", skip_reason: nil }.to_json,
        { subject: "s", body_html: body }.to_json
      ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.flagged_claims).to be_nil
    end
  end

  describe "thread_id selection" do
    it "is nil for cold intent" do
      fake_llm([ { subject: "s", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])
      result = described_class.draft_for_lead(lead, intent: :cold)
      expect(result.thread_id).to be_nil
    end

    it "uses the prior thread id for reengage intent" do
      account = Sendoff::EmailAccount.first
      allow_any_instance_of(Sendoff::Gmail::FakeClient).to receive(:fetch_messages_for).and_return([
        { gmail_thread_id: "thread-abc", account_email: account.email, account_name: "Dana Lee",
          direction: "outbound", subject: "first note", sent_at: 60.days.ago }
      ])
      fake_llm([ { subject: "first note", body_html: "<p>hi</p>", name_used: "Jordan", skip_reason: nil }.to_json ])
      result = described_class.draft_for_lead(lead, intent: :reengage)
      expect(result.thread_id).to eq("thread-abc")
    end
  end
end
