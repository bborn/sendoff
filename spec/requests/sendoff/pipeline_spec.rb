require "rails_helper"

RSpec.describe "Sendoff Pipeline", type: :request do
  include Sendoff::Engine.routes.url_helpers

  describe "GET /pipeline (index)" do
    it "renders 200 and groups entries by stage" do
      new_co  = create(:company)
      new_lead = create(:lead, company: new_co, full_name: "Casey Newman", email: "casey@newco.example")
      new_entry = create(:pipeline_entry, :new_stage, lead: new_lead, company: new_co)

      contacted_co = create(:company)
      contacted_lead = create(:lead, company: contacted_co, full_name: "Riley Reached", email: "riley@reached.example")
      contacted_entry = create(:pipeline_entry, :contacted, lead: contacted_lead, company: contacted_co)

      get pipeline_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Casey Newman")
      expect(response.body).to include("Riley Reached")
      # Both stage columns rendered.
      expect(response.body).to include("New")
      expect(response.body).to include("Contacted")
      # Cards carry their entry id for drag-drop.
      expect(response.body).to include("pipeline-entry-#{new_entry.id}")
      expect(response.body).to include("pipeline-entry-#{contacted_entry.id}")
    end

    it "hides the dud column by default and shows it with ?duds=1" do
      dud_lead = create(:lead, full_name: "Dud Person", email: "dud@example.com")
      create(:pipeline_entry, :dud, lead: dud_lead, company: dud_lead.company)

      get pipeline_path
      expect(response.body).not_to include("pipeline-entry-")

      get pipeline_path(duds: "1")
      expect(response.body).to include("Dud Person")
    end

    it "filters by segment" do
      agency_co = create(:company, :agency, segment: "agency")
      agency_lead = create(:lead, company: agency_co, full_name: "Agency Ann")
      create(:pipeline_entry, :new_stage, lead: agency_lead, company: agency_co)

      brand_co = create(:company, segment: "brand")
      brand_lead = create(:lead, company: brand_co, full_name: "Brand Bob")
      create(:pipeline_entry, :new_stage, lead: brand_lead, company: brand_co)

      get pipeline_path(segment: "agency")

      expect(response.body).to include("Agency Ann")
      expect(response.body).not_to include("Brand Bob")
    end

    it "filters by free-text query on name/email/company" do
      hit_lead = create(:lead, full_name: "Findable Fiona", email: "fiona@findable.example")
      create(:pipeline_entry, :new_stage, lead: hit_lead, company: hit_lead.company)

      miss_lead = create(:lead, full_name: "Hidden Harry", email: "harry@hidden.example")
      create(:pipeline_entry, :new_stage, lead: miss_lead, company: miss_lead.company)

      get pipeline_path(q: "findable")

      expect(response.body).to include("Findable Fiona")
      expect(response.body).not_to include("Hidden Harry")
    end
  end

  describe "PATCH /pipeline/:id/move (move)" do
    it "updates the stage and writes an audit log" do
      entry = create(:pipeline_entry, :new_stage)

      expect {
        patch move_pipeline_entry_path(entry), params: { stage: "review" }
      }.to change { Sendoff::AuditLog.where(action: "pipeline_stage_changed").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(entry.reload.stage).to eq("review")

      log = Sendoff::AuditLog.where(action: "pipeline_stage_changed").last
      expect(log.subject).to eq(entry)
      expect(log.detail).to include("new -> review")
    end

    it "rejects an unknown stage with 422 and does not change the entry" do
      entry = create(:pipeline_entry, :new_stage)

      patch move_pipeline_entry_path(entry), params: { stage: "bogus" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(entry.reload.stage).to eq("new")
    end

    it "rejects regression out of a protected stage (replied) with 422 and no change" do
      entry = create(:pipeline_entry, :replied)

      expect {
        patch move_pipeline_entry_path(entry), params: { stage: "new" }
      }.not_to change { Sendoff::AuditLog.where(action: "pipeline_stage_changed").count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(entry.reload.stage).to eq("replied")
    end

    it "rejects regression out of a protected stage (dud) with 422 and no change" do
      entry = create(:pipeline_entry, :dud)

      patch move_pipeline_entry_path(entry), params: { stage: "contacted" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(entry.reload.stage).to eq("dud")
    end

    it "allows a forward move from a non-protected stage" do
      entry = create(:pipeline_entry, :contacted)

      patch move_pipeline_entry_path(entry), params: { stage: "replied" }

      expect(response).to have_http_status(:ok)
      expect(entry.reload.stage).to eq("replied")
    end
  end
end
