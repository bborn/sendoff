require "rails_helper"

RSpec.describe Sendoff::Drafter::Context do
  let(:company) { create(:company, :preset_segment, segment: "brand", domain: "client.com", name: "Client Co") }
  let(:lead) { create(:lead, company: company, email: "jordan@client.com", name_source: "manual") }

  before { Rails.cache.clear }

  it "builds a context hash with lead, company, and account keys" do
    ctx = described_class.new(lead, intent: :cold).build
    expect(ctx[:lead][:email]).to eq("jordan@client.com")
    expect(ctx[:company][:name]).to eq("Client Co")
    expect(ctx[:company][:segment]).to eq("brand")
    expect(ctx).to have_key(:account)
    expect(ctx).to have_key(:brand_mentions_count)
  end

  it "uses config.account_lookup for the account field" do
    info = Sendoff::Adapters::AccountInfo.new(subdomain: "client", status: "active")
    allow(Sendoff.config.account_lookup).to receive(:find).with(lead).and_return(info)
    ctx = described_class.new(lead, intent: :checkin).build
    expect(ctx[:account]).to eq(info)
  end

  it "uses config.brand_mention_source for the brand_mentions_count" do
    source = Sendoff.config.brand_mention_source
    allow(source).to receive(:count_for).with(company).and_return(7)
    ctx = described_class.new(lead, intent: :cold).build
    expect(ctx[:brand_mentions_count]).to eq(7)
  end

  it "pulls active voice rules scoped to the intent" do
    Sendoff::VoiceRule.create!(scope: "all", rule: "always one", active: true)
    Sendoff::VoiceRule.create!(scope: "cold_prospect", rule: "cold two", active: true)
    Sendoff::VoiceRule.create!(scope: "reengage_cold", rule: "other three", active: true)

    ctx = described_class.new(lead, intent: :cold).build
    expect(ctx[:voice_rules]).to include("always one")
    expect(ctx[:voice_rules]).to include("cold two")
    expect(ctx[:voice_rules]).not_to include("other three")
  end

  it "surfaces a substantial research note as research_summary" do
    create(:note, notable: lead, body_md: ("- Name: Jordan Rivera\n" + ("detail. " * 60)))
    ctx = described_class.new(lead, intent: :cold).build
    expect(ctx[:research_summary]).to include("- Name: Jordan Rivera")
  end
end
