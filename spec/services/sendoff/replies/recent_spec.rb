require "rails_helper"

RSpec.describe Sendoff::Replies::Recent do
  let(:company) { create(:company, :preset_segment, segment: "brand", name: "Client Co") }
  let(:lead)    { create(:lead, company: company, email: "casey@client.com", full_name: "Casey Jones") }
  let(:account) { create(:email_account, :outreach, email: "dana@acme.test") }

  def our_send!(sent_at:, thread_id: "thread-1", subject: "Quick question")
    create(:email_event, lead: lead, company: company, direction: "outbound",
           email_account: account, from_addr: account.email, to_addrs: [ lead.email ],
           gmail_thread_id: thread_id, subject: subject, sent_at: sent_at)
  end

  def stub_history(messages)
    fake = Sendoff::Gmail::FakeClient.new(account)
    fake.messages = messages
    Sendoff.config.gmail_client_factory = ->(_a) { fake }
    Rails.cache.clear
  end

  it "detects a genuine inbound reply in our thread after our send" do
    our_send!(sent_at: 2.days.ago)
    stub_history([
      { direction: "inbound", sent_at: 1.day.ago, gmail_thread_id: "thread-1",
        subject: "Re: Quick question", body_text: "Sure, let's talk." }
    ])

    replies = described_class.call(days: 14)

    expect(replies.size).to eq(1)
    expect(replies.first).to include(lead_email: "casey@client.com", company: "Client Co")
    expect(replies.first[:snippet]).to eq("Sure, let's talk.")
  end

  it "filters out auto-replies (out of office)" do
    our_send!(sent_at: 2.days.ago)
    stub_history([
      { direction: "inbound", sent_at: 1.day.ago, gmail_thread_id: "thread-1",
        subject: "Automatic reply: Quick question", body_text: "I am out of office." }
    ])

    expect(described_class.call(days: 14)).to be_empty
  end

  it "ignores inbound messages outside our threads" do
    our_send!(sent_at: 2.days.ago, thread_id: "thread-1")
    stub_history([
      { direction: "inbound", sent_at: 1.day.ago, gmail_thread_id: "other-thread",
        subject: "Unrelated", body_text: "hi" }
    ])

    expect(described_class.call(days: 14)).to be_empty
  end

  it "ignores inbound messages we already replied to via a later Gmail-direct send" do
    our_send!(sent_at: 5.days.ago)
    stub_history([
      { direction: "inbound", sent_at: 3.days.ago, gmail_thread_id: "thread-1",
        subject: "Re: Quick question", body_text: "interested" },
      { direction: "outbound", sent_at: 2.days.ago, gmail_thread_id: "thread-1",
        subject: "Re: Quick question", body_text: "great, here's a link" }
    ])

    expect(described_class.call(days: 14)).to be_empty
  end
end
