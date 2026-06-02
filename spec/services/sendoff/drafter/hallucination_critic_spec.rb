require "rails_helper"

RSpec.describe Sendoff::Drafter::HallucinationCritic do
  let(:context) do
    { lead: { email: "jordan@client.com", first_name: "Jordan" },
      company: { name: "Client Co", domain: "client.com", segment: "brand" } }
  end

  it "passes when the LLM finds no unsupported claims" do
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(
      responses: [ { flagged_claims: [], reason: nil }.to_json ]
    )
    result = described_class.call(body_html: "<p>Hi Jordan.</p>", context: context)
    expect(result.ok?).to be(true)
    expect(result.flagged_claims).to eq([])
  end

  it "flags unsupported claims" do
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(
      responses: [ { flagged_claims: [ "500 partners" ], reason: "not in context" }.to_json ]
    )
    result = described_class.call(body_html: "<p>congrats on 500 partners</p>", context: context)
    expect(result.ok?).to be(false)
    expect(result.flagged_claims).to eq([ "500 partners" ])
  end

  it "passes through (ok) when disabled via config" do
    Sendoff.config.hallucination_critic_enabled = false
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new { |_| raise "should not be called" }
    result = described_class.call(body_html: "<p>anything</p>", context: context)
    expect(result.ok?).to be(true)
  end

  it "passes through on LLM error" do
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new { |_| raise "boom" }
    result = described_class.call(body_html: "<p>x</p>", context: context)
    expect(result.ok?).to be(true)
  end

  it "serializes an AccountInfo struct into the context without erroring" do
    acct = Sendoff::Adapters::AccountInfo.new(subdomain: "client", status: "active")
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(
      responses: [ { flagged_claims: [] }.to_json ]
    )
    result = described_class.call(body_html: "<p>x</p>", context: context.merge(account: acct))
    expect(result.ok?).to be(true)
  end
end
