require "rails_helper"

RSpec.describe Sendoff::LeadsSyncJob do
  it "calls Leads::Sync" do
    expect(Sendoff::Leads::Sync).to receive(:call)
    described_class.new.perform
  end

  it "runs end-to-end against the example source" do
    Sendoff.config.lead_source = Sendoff::Adapters::Example::LeadSource.new
    expect { described_class.new.perform }.to change { Sendoff::Lead.count }.from(0)
  end
end
