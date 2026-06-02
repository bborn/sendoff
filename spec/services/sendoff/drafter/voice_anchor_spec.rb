require "rails_helper"

RSpec.describe Sendoff::Drafter::VoiceAnchor do
  let(:account) { create(:email_account, :outreach) }

  before { Rails.cache.clear }

  it "returns recent sent engine Drafts when there are enough of them" do
    company = create(:company, :preset_segment, segment: "brand")
    4.times do |i|
      lead = create(:lead, company: company)
      create(:draft, lead: lead, email_account: account, status: "sent",
                     sent_at: i.days.ago, subject: "subject #{i}",
                     body_html: "<p>body #{i}</p><p>Thanks, Dana</p>")
    end

    examples = described_class.new(account).call
    expect(examples.size).to be >= 3
    expect(examples.first[:subject]).to be_present
    # Signature is stripped.
    expect(examples.first[:body_html]).not_to include("Thanks, Dana")
  end

  it "falls back to the Gmail sent folder when there are too few Drafts" do
    fake = Sendoff::Gmail::FakeClient.new(account)
    fake.recent_sent = [ { subject: "from gmail", body: "real body\nThanks, Dana" } ]
    Sendoff.config.gmail_client_factory = ->(_acct) { fake }

    examples = described_class.new(account).call
    expect(examples.size).to eq(1)
    expect(examples.first[:subject]).to eq("from gmail")
    expect(examples.first[:body_html]).to eq("real body")
  end

  it "filters engine Drafts by segment when provided" do
    brand_co = create(:company, :preset_segment, segment: "brand")
    agency_co = create(:company, :agency)
    agency_co.update!(segment: "agency")

    3.times do |i|
      create(:draft, lead: create(:lead, company: brand_co), email_account: account,
                     status: "sent", sent_at: i.days.ago, subject: "brand #{i}",
                     body_html: "<p>brand</p>")
    end
    create(:draft, lead: create(:lead, company: agency_co), email_account: account,
                   status: "sent", sent_at: 10.days.ago, subject: "agency one",
                   body_html: "<p>agency</p>")

    # Agency segment has only 1 draft -> below MIN, falls back to (empty) gmail.
    Sendoff.config.gmail_client_factory = ->(_acct) { Sendoff::Gmail::FakeClient.new(account) }
    examples = described_class.new(account, segment: "agency").call
    expect(examples).to eq([])
  end
end
