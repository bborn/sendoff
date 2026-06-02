require "rails_helper"

RSpec.describe Sendoff::Drafts::DeliverJob do
  let(:company) { create(:company, :preset_segment, segment: "brand") }
  let(:lead)    { create(:lead, company: company, email: "casey@client.com") }
  let(:account) { create(:email_account, :outreach, email: "dana@acme.test", display_name: "Dana Lee") }
  let(:draft) do
    create(:draft, lead: lead, email_account: account, status: "sending",
           to_addr: "casey@client.com", subject: "Hi", body_html: "<p>Hi</p>")
  end

  it "sends the draft via the Sender in immediate mode" do
    expect(Sendoff::Drafts::Sender).to receive(:call).with(draft, immediate: true)
    described_class.new.perform(draft.id)
  end

  it "no-ops when the draft is not in sending state" do
    draft.update_column(:status, "pending")
    expect(Sendoff::Drafts::Sender).not_to receive(:call)
    described_class.new.perform(draft.id)
  end

  it "resets the draft to pending on a rate-limit error" do
    allow(Sendoff::Drafts::Sender).to receive(:call)
      .and_raise(Sendoff::Drafts::RateLimitExceeded, "capped")

    described_class.new.perform(draft.id)

    expect(draft.reload).to be_pending
    expect(draft.send_job_id).to be_nil
  end
end
