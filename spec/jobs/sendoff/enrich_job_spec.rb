require "rails_helper"

RSpec.describe Sendoff::EnrichJob do
  # A plain-brand domain (no agency/nonprofit keywords) so we can drive the
  # company's segment to "unknown" and assert the job reclassifies it.
  let(:company) do
    c = create(:company, name: "Brightwave", domain: "brightwave.co")
    c.update_columns(segment: "unknown", segment_source: "test")
    c
  end
  let(:lead) do
    create(:lead, company: company, email: "kearns@brightwave.co",
           full_name: nil, first_name: nil, name_source: "email_prefix")
  end

  let(:summary) do
    <<~MD.strip
      === Research Summary ===
      - Name: Jane Doe
      - Title: Director of Marketing
      - Category: agency
      - Company details: a 30-person marketing agency
      - Recent activity: none found
      - Notes / flags: none
    MD
  end

  def use_llm_research(text)
    Sendoff.config.research_adapter = Sendoff::Adapters::LLMResearch.new
    Sendoff.config.llm_client = Sendoff::LLM::FakeClient.new(responses: [ text ])
  end

  describe "with an LLM research adapter" do
    before { use_llm_research(summary) }

    it "creates a Research Summary note authored by enrich_job" do
      expect { described_class.new.perform(lead.id) }
        .to change { lead.notes.count }.by(1)

      note = lead.notes.order(created_at: :desc).first
      expect(note.title).to eq("Research Summary (auto)")
      expect(note.body_md).to include("- Name: Jane Doe")
      expect(note.author).to eq("enrich_job")
      expect(note.source).to eq("llm")
    end

    it "reclassifies an unknown-segment company from the summary" do
      described_class.new.perform(lead.id)
      company.reload
      expect(company.segment).to eq("agency")
      expect(company.segment_source).to start_with("enrich:")
    end

    it "does NOT overwrite a manually-set segment" do
      company.update!(segment: "brand", segment_source: "manual")
      described_class.new.perform(lead.id)
      expect(company.reload.segment).to eq("brand")
    end

    it "writes a lead_enriched audit log" do
      expect { described_class.new.perform(lead.id) }
        .to change { Sendoff::AuditLog.where(action: "lead_enriched").count }.by(1)
    end

    it "skips a lead that is not enrichable unless forced" do
      lead.update!(name_source: "manual", first_name: "Sam", full_name: "Sam Lee")
      expect { described_class.new.perform(lead.id) }.not_to change { Sendoff::Note.count }
    end

    it "enriches a non-enrichable lead when force: true" do
      lead.update!(name_source: "manual", first_name: "Sam", full_name: "Sam Lee")
      expect { described_class.new.perform(lead.id, force: true) }
        .to change { lead.notes.count }.by(1)
    end

    it "no-ops for a missing lead" do
      expect { described_class.new.perform(SecureRandom.uuid) }
        .not_to change { Sendoff::Note.count }
    end
  end

  describe "with the default NullResearch adapter" do
    it "is a no-op: no note, no audit log" do
      # default adapter is NullResearch (set by reset_configuration!)
      expect(Sendoff.config.research_adapter).to be_a(Sendoff::Adapters::NullResearch)

      expect { described_class.new.perform(lead.id) }
        .to change { Sendoff::Note.count }.by(0)
      expect { described_class.new.perform(lead.id) }
        .to change { Sendoff::AuditLog.count }.by(0)
    end
  end
end
