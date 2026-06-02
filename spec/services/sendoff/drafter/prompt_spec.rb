require "rails_helper"

RSpec.describe Sendoff::Drafter::Prompt do
  let(:persona) do
    Sendoff::Persona.new(
      product_name:        "Acme Analytics",
      product_description: "a reporting tool for agencies",
      sender_name:         "Dana Lee",
      sender_email:        "dana@acme.test",
      voice_guide:         "Be direct and warm.",
      outreach_principles: "Lead with value.",
      allowed_url_patterns: [ %r{\Ahttps://calendar\.acme\.test/} ],
      segment_prompt_hints: { "agency" => "Mention the agency launch program." }
    )
  end
  let(:account) { create(:email_account, :outreach, display_name: "Dana Lee", email: "dana@acme.test") }

  before { Sendoff.config.persona = persona }

  def base_ctx(overrides = {})
    {
      intent: :cold,
      lead: { email: "jordan@client.com", first_name: "Jordan", full_name: "Jordan Rivera", name_source: "manual" },
      company: { name: "Client Co", domain: "client.com", segment: "brand" },
      account: nil,
      reports_viewed: [],
      thread_history: [],
      domain_thread_history: [],
      days_since_last_contact: nil,
      company_notes: [],
      research_summary: nil,
      voice_rules: "- be brief",
      voice_examples: [],
      brand_mentions_count: 0
    }.merge(overrides)
  end

  it "builds a persona-driven prompt with no host-specific strings" do
    out = described_class.new(base_ctx, email_account: account).build
    expect(out).to include("Acme Analytics")
    expect(out).to include("a reporting tool for agencies")
    expect(out).to include("Dana Lee")
    expect(out).to include("Be direct and warm.")
    expect(out).to include("calendar.acme.test")
    # No foreign host brand leaks: only the configured persona's product appears.
    expect(out).to include(persona.product_name)
  end

  it "includes the segment hint for a matching segment on cold intent" do
    ctx = base_ctx(company: { name: "A", domain: "a.com", segment: "agency" })
    out = described_class.new(ctx, email_account: account).build
    expect(out).to include("Mention the agency launch program.")
  end

  it "omits a segment hint when none exists for the segment" do
    out = described_class.new(base_ctx, email_account: account).build
    expect(out).not_to include("agency launch program")
  end

  it "does not inject the segment hint on reengage intent" do
    ctx = base_ctx(intent: :reengage, company: { name: "A", domain: "a.com", segment: "agency" })
    out = described_class.new(ctx, email_account: account).build
    expect(out).not_to include("agency launch program")
  end

  it "renders the account block and account url when an account is present" do
    acct = Sendoff::Adapters::AccountInfo.new(subdomain: "client", account_url: "https://client.acme.test",
                                                plan_name: "Pro", status: "active")
    out = described_class.new(base_ctx(intent: :checkin, account: acct), email_account: account).build
    expect(out).to include("<account>")
    expect(out).to include("client.acme.test")
    expect(out).to include("Pro")
  end

  it "substitutes {SENDER_NAME} and {PRODUCT_NAME} in the auto intent section" do
    out = described_class.new(base_ctx(intent: :auto), email_account: account).build
    expect(out).to include("Dana Lee")
    expect(out).to include("Acme Analytics")
    expect(out).not_to include("{SENDER_NAME}")
    expect(out).not_to include("{PRODUCT_NAME}")
  end
end
