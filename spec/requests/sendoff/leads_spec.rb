require "rails_helper"

module Sendoff
  RSpec.describe "Leads", type: :request do
    include Engine.routes.url_helpers

    describe "GET /leads (index)" do
      it "renders 200 and lists leads" do
        brand  = create(:company, segment: "brand")
        agency = create(:company, :agency, segment: "agency")
        lead_a = create(:lead, company: brand, email: "alice@brand.example")
        lead_b = create(:lead, company: agency, email: "bob@agency.example")

        get leads_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(lead_a.email)
        expect(response.body).to include(lead_b.email)
      end

      it "respects the segment filter" do
        brand  = create(:company, segment: "brand")
        agency = create(:company, :agency, segment: "agency")
        in_seg  = create(:lead, company: agency, email: "match@agency.example")
        out_seg = create(:lead, company: brand, email: "nomatch@brand.example")

        get leads_path(segment: "agency")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(in_seg.email)
        expect(response.body).not_to include(out_seg.email)
      end

      it "respects the free-text search filter" do
        company = create(:company)
        hit  = create(:lead, company: company, email: "findme@example.com", full_name: "Find Me")
        miss = create(:lead, company: company, email: "other@example.com", full_name: "Other Person")

        get leads_path(q: "findme")

        expect(response.body).to include(hit.email)
        expect(response.body).not_to include(miss.email)
      end
    end

    describe "GET /leads/:id (show)" do
      let(:lead) { create(:lead) }

      it "renders 200 with notes and a clipboard copy button" do
        create(:note, :on_lead, notable: lead, title: "Research Summary (auto)", body_md: "Useful research.")

        get lead_path(lead)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(lead.email)
        expect(response.body).to include("Useful research.")
        expect(response.body).to include("clipboard#copy")
      end

      it "does not 500 when Gmail history raises (no creds)" do
        allow(Sendoff::Gmail::History).to receive(:for_lead).and_raise(StandardError, "no creds")

        get lead_path(lead)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No email history")
      end
    end

    describe "POST /leads/:id/enrich" do
      let(:lead) { create(:lead) }

      it "enqueues EnrichJob and writes an audit log" do
        expect {
          post enrich_lead_path(lead)
        }.to have_enqueued_job(Sendoff::EnrichJob).with(lead.id, force: true)

        expect(AuditLog.where(action: "enrich_queued", subject_id: lead.id)).to exist
      end
    end

    describe "POST /leads/:id/queue" do
      let(:lead) { create(:lead) }

      it "moves the pipeline entry to drafting and writes an audit log" do
        PipelineEntry.skip_draft_callbacks do
          post queue_lead_path(lead)
        end

        entry = PipelineEntry.find_by(lead_id: lead.id)
        expect(entry).to be_present
        expect(entry.stage).to eq("drafting")
        expect(AuditLog.where(action: "lead_queued", subject_id: lead.id)).to exist
      end
    end

    describe "POST /leads/:id/skip" do
      let(:lead) { create(:lead) }

      it "creates a HiddenLead and an audit log" do
        expect {
          post skip_lead_path(lead)
        }.to change(HiddenLead, :count).by(1)

        expect(HiddenLead.find_by(lead_id: lead.id)).to be_present
        expect(AuditLog.where(action: "lead_skipped", subject_id: lead.id)).to exist
      end
    end

    describe "POST /leads/:id/unskip" do
      let(:lead) { create(:lead) }

      it "destroys the HiddenLead and writes an audit log" do
        create(:hidden_lead, lead: lead)

        expect {
          post unskip_lead_path(lead)
        }.to change(HiddenLead, :count).by(-1)

        expect(AuditLog.where(action: "lead_unskipped", subject_id: lead.id)).to exist
      end
    end
  end
end
