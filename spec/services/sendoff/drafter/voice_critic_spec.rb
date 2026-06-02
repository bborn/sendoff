require "rails_helper"

RSpec.describe Sendoff::Drafter::VoiceCritic do
  let(:persona) do
    Sendoff::Persona.new(product_name: "Acme Analytics", sender_name: "Dana Lee",
                           sender_email: "dana@acme.test")
  end

  before { Sendoff.config.persona = persona }

  it "returns the rewritten subject and body from the LLM" do
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(
      responses: [ { subject: "cleaner subject", body_html: "<p>I noticed you signed up.</p>" }.to_json ]
    )
    result = described_class.call(subject: "Noticed signup", body_html: "<p>Noticed you signed up.</p>")
    expect(result.subject).to eq("cleaner subject")
    expect(result.body_html).to include("I noticed")
  end

  it "builds a generic prompt from the persona (no host-specific names)" do
    client = Sendoff::LLM::FakeClient.new(responses: [ { subject: "s", body_html: "<p>x</p>" }.to_json ])
    Sendoff.config.llm_client = client
    described_class.call(subject: "s", body_html: "<p>x</p>")
    prompt = client.prompts.first
    expect(prompt).to include("Acme Analytics")
    expect(prompt).to include("Dana Lee")
    # No foreign host brand leaks: only the configured persona's product appears.
    expect(prompt).to include(persona.product_name)
  end

  it "returns the original on LLM error" do
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new { |_| raise "boom" }
    result = described_class.call(subject: "keep me", body_html: "<p>keep me too</p>")
    expect(result.subject).to eq("keep me")
    expect(result.body_html).to eq("<p>keep me too</p>")
  end

  describe "brand-mention postflight gate" do
    it "raises when a brand-mention claim survives and count is 0" do
      Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(
        responses: [ { subject: "s", body_html: "<p>people in our network posting about you</p>" }.to_json ]
      )
      expect {
        described_class.call(subject: "s", body_html: "<p>x</p>", brand_mentions_count: 0)
      }.to raise_error(Sendoff::Drafter::VoiceCritic::UnverifiedBrandMentionClaim)
    end

    it "does not raise when the count is positive" do
      Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(
        responses: [ { subject: "s", body_html: "<p>people talking about you</p>" }.to_json ]
      )
      expect {
        described_class.call(subject: "s", body_html: "<p>x</p>", brand_mentions_count: 5)
      }.not_to raise_error
    end
  end
end
