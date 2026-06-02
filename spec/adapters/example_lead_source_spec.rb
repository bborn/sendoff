require "rails_helper"

RSpec.describe Sendoff::Adapters::Example::LeadSource do
  subject(:source) { described_class.new }

  it "is a LeadSource" do
    expect(source).to be_a(Sendoff::Adapters::LeadSource)
  end

  describe "#fetch" do
    let(:leads) { source.fetch }

    it "returns a non-trivial array of LeadData" do
      expect(leads).to be_an(Array)
      expect(leads.size).to be_between(8, 12)
      expect(leads).to all(be_a(Sendoff::Adapters::LeadData))
    end

    it "gives every lead a parseable email" do
      leads.each do |ld|
        expect(ld.email).to match(URI::MailTo::EMAIL_REGEXP)
      end
    end

    it "provides warmth signals as a hash on every lead" do
      leads.each { |ld| expect(ld.signals).to be_a(Hash) }
    end

    it "includes at least one personal/free-email address to exercise the skiplist" do
      domains = leads.map { |ld| ld.email.split("@").last }
      expect(domains).to include(a_string_matching(/gmail\.com|yahoo\.com/))
    end

    it "spans multiple distinct company domains" do
      domains = leads.map(&:company_domain).compact.uniq
      expect(domains.size).to be >= 5
    end

    it "includes a lead with an explicit segment hint" do
      expect(leads.map(&:segment).compact).to include(:nonprofit)
    end

    it "includes a lead with no name fields (email-prefix derivation)" do
      bare = leads.find { |ld| ld.full_name.blank? && ld.first_name.blank? && ld.last_name.blank? }
      expect(bare).not_to be_nil
    end
  end
end
