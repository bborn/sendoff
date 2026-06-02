require "rails_helper"

module Sendoff
  module Adapters
    RSpec.describe Research do
      describe NullResearch do
        it "is a Research adapter" do
          expect(described_class.new).to be_a(Research)
        end

        it "returns nil (enrichment no-op)" do
          lead = create(:lead)
          expect(described_class.new.research(lead)).to be_nil
        end
      end

      describe Research, "base class" do
        it "raises NotImplementedError" do
          lead = create(:lead)
          expect { described_class.new.research(lead) }.to raise_error(Sendoff::NotImplementedError)
        end
      end

      describe LLMResearch do
        let(:company) { create(:company, name: "Brightwave Media", domain: "brightwavemedia.com", segment: "unknown") }
        let(:lead) do
          create(:lead, company: company, email: "kearns@brightwavemedia.com",
                        full_name: nil, first_name: nil, name_source: "email_prefix")
        end

        it "is a Research adapter" do
          expect(described_class.new).to be_a(Research)
        end

        it "builds a prompt containing the lead's email and company, and returns the client's output" do
          summary = "=== Research Summary ===\n- Name: Jane Doe\n- Category: agency"
          fake = Sendoff::LLM::FakeClient.new(responses: [ summary ])
          Sendoff.config.llm_client = fake

          result = described_class.new.research(lead)

          expect(result).to eq(summary)
          prompt = fake.prompts.first
          expect(prompt).to include("kearns@brightwavemedia.com")
          expect(prompt).to include("Brightwave Media")
          expect(prompt).to include("brightwavemedia.com")
        end

        it "instructs the model to emit a '- Name:' line (Drafter::Context contract)" do
          fake = Sendoff::LLM::FakeClient.new(responses: [ "x" ])
          Sendoff.config.llm_client = fake
          described_class.new.research(lead)

          prompt = fake.prompts.first
          expect(prompt).to include("- Name:")
          expect(prompt).to include("=== Research Summary ===")
        end

        it "references the engine's generic segment taxonomy" do
          fake = Sendoff::LLM::FakeClient.new(responses: [ "x" ])
          Sendoff.config.llm_client = fake
          described_class.new.research(lead)

          prompt = fake.prompts.first.downcase
          expect(prompt).to include("agency")
          expect(prompt).to include("brand")
          expect(prompt).to include("nonprofit")
        end

        it "contains no host-specific / heavy-dependency references" do
          fake = Sendoff::LLM::FakeClient.new(responses: [ "x" ])
          Sendoff.config.llm_client = fake
          described_class.new.research(lead)

          prompt = fake.prompts.first.downcase
          %w[influencekit firecrawl psql flex].each do |banned|
            expect(prompt).not_to include(banned)
          end
        end

        it "strips ANSI escapes and returns nil for blank output" do
          Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: [ "   " ])
          expect(described_class.new.research(lead)).to be_nil
        end
      end
    end
  end
end
